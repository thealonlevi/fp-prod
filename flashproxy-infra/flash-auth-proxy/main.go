package main

import (
	"bufio"
	"context"
	"encoding/base64"
	"errors"
	"flag"
	"fmt"
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
	redisPwd = flag.String("redis-password", os.Getenv("REDIS_PASS"), "Redis AUTH password")
	maxGbps  = flag.Float64("max-gbps", 1, "Per-user bandwidth cap (Gb/s)")
)

/* ───── globals (init in main) ─────────────────────────────── */

var (
	ctx context.Context
	rdb *redis.Client
)

/* ───── helpers ─────────────────────────────────────────────── */

func parseBasicAuth(h string) (string, string, error) {
	if !strings.HasPrefix(h, "Basic ") {
		return "", "", errors.New("no Basic prefix")
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

const bdHeader = "Proxy-Authorization: Basic " +
	"YnJkLWN1c3RvbWVyLWhsXzE5Y2IwZmU4LXpvbmUtYWw0LWNvdW50cnktVVMtc2Vzc2lvbi0xMjM0NTY3ODowMzVrbngzM2RtbjI="

func handleConn(c net.Conn) {
	defer c.Close()
	tp := textproto.NewReader(bufio.NewReader(c))

	/* ① CONNECT line */
	connectLine, err := tp.ReadLine()
	if err != nil || !strings.HasPrefix(connectLine, "CONNECT ") {
		io.WriteString(c, "HTTP/1.1 400 Bad Request\r\n\r\n")
		return
	}

	/* ② read headers, find Proxy-Authorization */
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
		io.WriteString(c, "HTTP/1.1 407 Proxy Authentication Required\r\n"+
			"Proxy-Authenticate: Basic realm=\"FlashProxy\"\r\n\r\n")
		return
	}
	user, pass, err := parseBasicAuth(authHdr)
	if err != nil || !passwdOK(user, pass) {
		io.WriteString(c, "HTTP/1.1 407 Proxy Authentication Required\r\n"+
			"Proxy-Authenticate: Basic realm=\"FlashProxy\"\r\n\r\n")
		return
	}

	/* ③ per-user 1 Gb/s (~125 MB/s) sliding window */
	limitBytes := int64(*maxGbps * 125_000_000)
	bwKey := "bw:" + user

	/* ④ dial downstream (HAProxy) */
	ds, err := net.Dial("tcp", *backend)
	if err != nil {
		io.WriteString(c, "HTTP/1.1 502 Bad Gateway\r\n\r\n")
		return
	}
	defer ds.Close()

	/* ⑤ send new CONNECT with Bright Data creds */
	fmt.Fprintf(ds, "%s\r\n%s\r\n\r\n", connectLine, bdHeader)

	/* ⑥ tell client OK, then tunnel */
	io.WriteString(c, "HTTP/1.1 200 Connection Established\r\n\r\n")

	pipe := func(dst, src net.Conn) {
		buf := make([]byte, 64*1024)
		for {
			n, err := src.Read(buf)
			if n > 0 {
				if atomic.AddInt64(new(int64), int64(n)); rdb.IncrBy(ctx, bwKey, int64(n)).Val() > limitBytes {
					rdb.Expire(ctx, bwKey, time.Second)
					dst.Close()
					src.Close()
					return
				}
				dst.Write(buf[:n])
			}
			if err != nil {
				return
			}
		}
	}
	go pipe(ds, c)
	pipe(c, ds)
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
		if c, err := ln.Accept(); err == nil {
			go handleConn(c)
		}
	}
}
