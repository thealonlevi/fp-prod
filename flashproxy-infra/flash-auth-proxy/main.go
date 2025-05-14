package main

import (
	"bufio"
	"context"
	"encoding/base64"
	"errors"
	"flag"
	"io"
	"log"
	"net"
	"net/textproto"
	"strings"
	"sync/atomic"
	"time"

	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"
)

/* ───── CLI flags ───────────────────────────────────────────── */

var (
	listen   = flag.String("listen", ":443", "Public listen address")
	backend  = flag.String("backend", "127.0.0.1:8443", "HAProxy address")
	redisURL = flag.String("redis", "127.0.0.1:6379", "Redis host:port")
	redisPwd = flag.String("redis-password", "", "Redis AUTH password")
	maxGbps  = flag.Float64("max-gbps", 1, "Per-user bandwidth cap (Gb/s)")
)

/* ───── Redis ───────────────────────────────────────────────── */

var (
	rdb = redis.NewClient(&redis.Options{
		Addr: *redisURL, Password: *redisPwd, DialTimeout: 500 * time.Millisecond,
	})
	ctx = context.Background()
)

/* ───── helpers ─────────────────────────────────────────────── */

func parseBasicAuth(h string) (user, pass string, err error) {
	if !strings.HasPrefix(h, "Basic ") {
		return "", "", errors.New("missing Basic prefix")
	}
	dec, err := base64.StdEncoding.DecodeString(strings.TrimSpace(h[6:]))
	if err != nil {
		return "", "", err
	}
	parts := strings.SplitN(string(dec), ":", 2)
	if len(parts) != 2 {
		return "", "", errors.New("bad auth pair")
	}
	return parts[0], parts[1], nil
}

func passwdOK(user, pass string) bool {
	hash, err := rdb.HGet(ctx, "user:"+user, "pwd").Result()
	if err != nil {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(pass)) == nil
}

/* ───── main loop ───────────────────────────────────────────── */

func handleConn(br net.Conn) {
	defer br.Close()
	tp := textproto.NewReader(bufio.NewReader(br))

	// ① first line
	reqLine, err := tp.ReadLine()
	if err != nil || !strings.HasPrefix(reqLine, "CONNECT ") {
		io.WriteString(br, "HTTP/1.1 400 Bad Request\r\n\r\n")
		return
	}

	// ② headers
	var (
		user     string
		bAuthHdr string
	)
	for {
		l, _ := tp.ReadLine()
		if l == "" {
			break
		}
		if strings.HasPrefix(strings.ToLower(l), "proxy-authorization:") {
			bAuthHdr = strings.TrimSpace(l[len("proxy-authorization:"):])
		}
	}
	if bAuthHdr == "" {
		io.WriteString(br, "HTTP/1.1 407 Proxy Authentication Required\r\n"+
			"Proxy-Authenticate: Basic realm=\"FlashProxy\"\r\n\r\n")
		return
	}
	u, p, err := parseBasicAuth(bAuthHdr)
	if err != nil || !passwdOK(u, p) {
		io.WriteString(br, "HTTP/1.1 407 Proxy Authentication Required\r\n"+
			"Proxy-Authenticate: Basic realm=\"FlashProxy\"\r\n\r\n")
		return
	}
	user = u // save for quota keys

	// ③ bandwidth token-bucket (1-second window)
	limitBytes := int64(*maxGbps * 125_000_000) // Gb/s → B/s
	key := "bw:" + user

	// ④ connect downstream
	ds, err := net.Dial("tcp", *backend)
	if err != nil {
		io.WriteString(br, "HTTP/1.1 502 Bad Gateway\r\n\r\n")
		return
	}
	defer ds.Close()

	io.WriteString(br, "HTTP/1.1 200 Connection Established\r\n\r\n")

	// ⑤ pipe data both ways while counting
	var up, down int64
	copyCount := func(dst, src net.Conn, counter *int64) {
		buf := make([]byte, 64*1024)
		for {
			n, err := src.Read(buf)
			if n > 0 {
				atomic.AddInt64(counter, int64(n))
				// sliding-window quota
				if v := rdb.IncrBy(ctx, key, int64(n)).Val(); v > limitBytes {
					// over limit → drop conn for 1 s
					rdb.Expire(ctx, key, time.Second)
					br.Close()
					ds.Close()
					return
				}
				dst.Write(buf[:n])
			}
			if err != nil {
				return
			}
		}
	}
	go copyCount(ds, br, &up)
	copyCount(br, ds, &down)
}

func main() {
	flag.Parse()

	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Fatalf("redis ping: %v", err)
	}

	ln, err := net.Listen("tcp", *listen)
	if err != nil {
		log.Fatalf("listen: %v", err)
	}
	log.Printf("auth-proxy listening on %s → %s", *listen, *backend)

	for {
		c, err := ln.Accept()
		if err != nil {
			continue
		}
		go handleConn(c)
	}
}
