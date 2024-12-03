---  
share: true  
aliases:  
  - Optimizing Webservers for High Throughput and Low Latency | Dropbox  
title: Optimizing Webservers for High Throughput and Low Latency | Dropbox  
URL: https://youtu.be/aGL8a3Agj-c  
Author:   
Platform:   
Channel:   
tags:   
---  
[Home](../index.md) > [Videos](./index.md)  
# Optimizing Webservers for High Throughput and Low Latency | Dropbox  
![Optimizing Webservers for High Throughput and Low Latency | Dropbox](https://youtu.be/aGL8a3Agj-c)  
  
- paper: Making Linux TCP Fast  
  - fair queueing and pacing  
    - decreases retransmit rates  
  - congestion control  
    - tcp_cubic -> tcp_bbr  
  - ack processing & loss detection  
    - use newer kernels  
      - new heuristics enabled by default  
      - upgrade your kernel  
    - sysctl   
      - don't  
        - enable time wait recycle  
        - disable timestamps unless you know what you're doing  
      - do  
        - disable slow start after idle  
        - enable TCP mtu probing  
        - increase read and write memory - match to BDP  
- libraries  
  - lots of time spent in compression?  
    - zlib forks by cloud flare & Intel; zlib-gz  
    - Malloc?  
      - jemalloc  
      - tcmalloc  
    - pcre symbols in perftop?  
      - consider JIT  
  - TLS  
    - openssl, libressl, boringssl  
    - symmetric encryption  
      - big files?  
        - openssl symbols in perftop  
          - enable chacha20-poly1305  
- nginx  
  - what to compress  
  - when to compress  
    - brotli for static content as a build step  
    - optimize for round trip time  
      - encrypt, transmit, decrypt  
  - buffering  
    - x-accel-buffering  
  - TLS  
    - session resumption  
      - sticky load balancing or distributed cache  
      - tickets - no server side state  
    - TLS record sizes  
  - event loop stalling  
    - aio_write  
- global optimizations  
  - load balancing  
  - inbound & outbound traffic engineering  
  - Twitter: @SaveTheRbtz  
