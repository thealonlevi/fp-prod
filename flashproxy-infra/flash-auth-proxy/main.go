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
	"os"
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
	// default to $REDIS_PASS so the flag is optional
	redisPwd = flag.String("redis-password", os.Getenv("REDIS_PASS"), "Redis AUTH password")
	maxGbps  = flag.Float64("max-gbps", 1, "Per-user bandwidth cap (Gb/s)")
)

/* ───── global vars initialised in main() ───────────────────── */
var (
	ctx context.Context
	rdb *redis.Client
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

/* ───── per-connection handler ─────────────────────────────── */

func handleConn(br net.Conn) {
	defer br.Close()
	tp := textproto.NewReader(bufio.NewReader(br))

	// ① CONNECT line
	first, err := tp.ReadLine()
	if err != nil || !strings.HasPrefix(first, "CONNECT ") {
		io.WriteString(br, "HTTP/1.1 400 Bad Request\r\n\r\n")
		return
	}

	// ② headers
	var authHdr string
	for {
		l, _ := tp.ReadLine()
		if l == "" {
			break
		}
		if strings.HasPrefix(strings.ToLower(l), "proxy-authorization:") {
			authHdr = strings.TrimSpace(l[len("proxy-authorization:"):])
		}
	}
	if authHdr == "" {
		io.WriteString(br, "HTTP/1.1 407 Proxy Authentication Required\r\n"+
			"Proxy-Authenticate: Basic realm=\"FlashProxy\"\r\n\r\n")
		return
	}
	user, pass, err := parseBasicAuth(authHdr)
	if err != nil || !passwdOK(user, pass) {
		io.WriteString(br, "HTTP/1.1 407 Proxy Authentication Required\r\n"+
			"Proxy-Authenticate: Basic realm=\"FlashProxy\"\r\n\r\n")
		return
	}

	// ③ per-user 1-second bandwidth window
	limitBytes := int64(*maxGbps * 125_000_000) // Gb/s → bytes
	bwKey := "bw:" + user

	// ④ dial HAProxy
	ds, err := net.Dial("tcp", *backend)
	if err != nil {
		io.WriteString(br, "HTTP/1.1 502 Bad Gateway\r\n\r\n")
		return
	}
	defer ds.Close()

	io.WriteString(br, "HTTP/1.1 200 Connection Established\r\n\r\n")

	// ⑤ bidirectional copy + quota
	copyCount := func(dst, src net.Conn, counter *int64) {
		buf := make([]byte, 64*1024)
		for {
			n, err := src.Read(buf)
			if n > 0 {
				atomic.AddInt64(counter, int64(n))
				if v := rdb.IncrBy(ctx, bwKey, int64(n)).Val(); v > limitBytes {
					rdb.Expire(ctx, bwKey, time.Second)
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

	go copyCount(ds, br, new(int64)) // upstream
	copyCount(br, ds, new(int64))    // downstream
}

/* ───── main ───────────────────────────────────────────────── */

func main() {
	flag.Parse()

	ctx = context.Background()
	rdb = redis.NewClient(&redis.Options{
		Addr: *redisURL, Password: *redisPwd, DialTimeout: 500 * time.Millisecond,
	})
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
		if err == nil {
			go handleConn(c)
		}
	}
}
