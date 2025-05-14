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

/* ───── globals initialised in main() ──────────────────────── */
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

func handleConn(cli net.Conn) {
	defer cli.Close()
	tp := textproto.NewReader(bufio.NewReader(cli))

	// ① CONNECT line from client
	reqLine, err := tp.ReadLine()
	if err != nil || !strings.HasPrefix(reqLine, "CONNECT ") {
		io.WriteString(cli, "HTTP/1.1 400 Bad Request\r\n\r\n")
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
		io.WriteString(cli, "HTTP/1.1 407 Proxy Authentication Required\r\n"+
			"Proxy-Authenticate: Basic realm=\"FlashProxy\"\r\n\r\n")
		return
	}
	user, pass, err := parseBasicAuth(authHdr)
	if err != nil || !passwdOK(user, pass) {
		io.WriteString(cli, "HTTP/1.1 407 Proxy Authentication Required\r\n"+
			"Proxy-Authenticate: Basic realm=\"FlashProxy\"\r\n\r\n")
		return
	}

	// ③ per-user bandwidth window (1 s)
	limitBytes := int64(*maxGbps * 125_000_000)
	bwKey := "bw:" + user

	// ④ dial downstream (HAProxy)
	ds, err := net.Dial("tcp", *backend)
	if err != nil {
		io.WriteString(cli, "HTTP/1.1 502 Bad Gateway\r\n\r\n")
		return
	}
	defer ds.Close()

	/* ⑤ send a fresh CONNECT with Bright Data creds */
	fmt.Fprintf(ds, "%s\r\n", reqLine)
	fmt.Fprint(ds, "Proxy-Authorization: Basic "+
		"YnJkLWN1c3RvbWVyLWhsXzE5Y2IwZmU4LXpvbmUtYWw0LWNvdW50cnktVVMtc2Vzc2lvbi0xMjM0NTY3ODowMzVrbngzM2RtbjI=\r\n\r\n")

	/* read 1-line response from downstream and relay to client */
	dsResp := bufio.NewReader(ds)
	status, _ := dsResp.ReadString('\n')
	if !strings.HasPrefix(status, "HTTP/1.1 200") {
		cli.Write([]byte(status))
		io.Copy(cli, dsResp)
		return
	}
	// consume rest of downstream headers
	for {
		line, _ := dsResp.ReadString('\n')
		if line == "\r\n" || line == "\n" {
			break
		}
	}
	cli.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n"))

	// ⑥ bidirectional copy with quota
	pipe := func(dst, src net.Conn, key string) {
		buf := make([]byte, 64*1024)
		for {
			n, err := src.Read(buf)
			if n > 0 {
				if v := rdb.IncrBy(ctx, key, int64(n)).Val(); v > limitBytes {
					rdb.Expire(ctx, key, time.Second)
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
	go pipe(ds, cli, bwKey) // upstream
	pipe(cli, ds, bwKey)    // downstream
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
