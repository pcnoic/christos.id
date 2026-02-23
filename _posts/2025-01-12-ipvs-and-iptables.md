---
layout: post
title: exotic networking patterns for load balancing that you probably don't need
date: 2025-02-23
last_modified_at: 2025-02-23
preview: true
description: Deep dive into IPVS vs iptables for Kubernetes load balancing, exploring when exotic networking patterns actually matter for bare-metal clusters.
topic: distributed-systems
tldr: IPVS offers O(1) lookup vs iptables' O(n) for large service counts, but most clusters don't need it. Consider IPVS only if you have 1000+ services or need advanced scheduling algorithms.
tags:
  - kubernetes
  - networking
  - load-balancing
  - ipvs
  - iptables
references:
  - title: "Dynatrace: Kubernetes in the Wild 2023"
    url: https://www.dynatrace.com/news/blog/kubernetes-in-the-wild-2023/
  - title: "Kubernetes IPVS-Based In-Cluster Load Balancing"
    url: https://kubernetes.io/blog/2018/07/09/ipvs-based-in-cluster-load-balancing-deep-dive/
  - title: "Cilium"
    url: https://cilium.io/
---

After sacrificing a few hours in the quest of finding the optimal bare-metal k8s setup for a project I am working on (more on that on a different blog post), I found myself jumping into the rabbit hole of some exotic networking patterns used in modern Kubernetes load balancing. According to a post from [Dynatrace](https://www.dynatrace.com/news/blog/kubernetes-in-the-wild-2023/#:~:text=A%20typical%20cluster%20running%20in,reflects%20economic%20and%20technical%20considerations.) "a typical cluster running in the public cloud consists of 5 relatively small nodes with just 16 to 32 GB of memory each. In comparison, on-premises clusters have more and larger nodes: on average, 9 nodes with 32 to 64 GB of memory." So, when I remembered that kube-proxy added support for IPVS starting version 1.8 and GA in 1.11 my secondary reaction was doubt. Probably my initial was indifference, because when k8s 1.8 was current, I didn't know much about Kubernetes. Or networks. Or computers to be honest.

Despite my late blooming into the computing industry, I now know that there are probably a handful of organizations in the world that would benefit from lower computational complexity. Where I could see benefit for more people was the fact that IPVS was designed inherently as a load balancer so the availability of scheduling algorithms is broader. The randomized, equal-cost selection of iptables when redirecting traffic is, indeed, suboptimal.

### A bit of iptables and IPVS history

Netfilter is the original Linux kernel's packet processing system. The commonplace name `iptables` came from the command that is used to interact with it, and because of their extremely tight coupling, and `iptables` being one of the most used commands in network computing, I'll refer to both as `iptables`, even when talking about the Netfilter framework. The architecture of `iptables` groups network packet processing rules into tables by function (e.g packet filtering, NAT, and other packet mangling), each of which have chains of processing rules that consist of matches.

```mermaid
graph LR
    A[tables] --> B[rule chains]
    B --> C[matches]
```

Examining it in reverse, the matches are used to determine which packets the rule will apply to and targets determine what will be done with the matching packets.

<style>
    :root {
        --bg: #0d0d0d;
        --panel: #1a1a1a;
        --rule: #2b2b2b;
        --text: #c8f7c5;
        --highlight: #f2d675;
        --nomatch: #b34747;
        --accept: #2ecc71;
    }

    #iptables-scene {
        font-family: monospace;
        padding: 20px;
        border: 1px solid #333;
        background-color: var(--bg);
        color: var(--text);
        width: 700px;
        max-width: 100%;
        box-sizing: border-box;
        margin: 30px auto;
        border-radius: 10px;
        position: relative;
        overflow-x: hidden;
    }

    h2 {
        text-align: center;
        margin-top: 0;
        margin-bottom: 15px;
        color: var(--highlight);
        font-size: 1.4em;
    }

    .chain-container {
        background: var(--panel);
        border: 1px solid #333;
        padding: 15px;
        border-radius: 8px;
        margin-bottom: 15px;
    }

    .rule {
        background: var(--rule);
        border: 1px solid #444;
        padding: 10px;
        margin-bottom: 8px;
        display: flex;
        justify-content: space-between;
        align-items: center;
        border-radius: 6px;
        transition: border-color 0.3s, box-shadow 0.3s;
    }

    .rule.matching {
        border-color: var(--highlight);
        box-shadow: 0 0 10px #f2d67580;
    }

    .rule.nomatch {
        border-color: var(--nomatch);
        opacity: 0.7;
    }

    .action-box {
        margin-top: 10px;
        padding: 12px;
        border: 2px dashed var(--highlight);
        text-align: center;
        background: #111;
        border-radius: 6px;
    }

    .packet {
        position: absolute;
        top: 80px;
        left: -120px;
        width: 150px;
        height: 32px;
        line-height: 32px;
        background: #007bff;
        color: white;
        text-align: center;
        border-radius: 5px;
        box-shadow: 0 0 10px #007bff;
        transition: transform 1.4s ease-in-out, box-shadow 0.4s, background-color 0.4s;
        z-index: 100;
    }

    .packet.accepted {
        background: var(--accept);
        box-shadow: 0 0 12px var(--accept);
    }

    #console {
        background: #111;
        border: 1px solid #333;
        padding: 10px;
        height: 110px;
        font-size: 0.9em;
        overflow-y: auto;
        border-radius: 6px;
        white-space: pre-line;
    }

    button {
        display: block;
        margin: 20px auto 0;
        padding: 10px 25px;
        background: var(--highlight);
        border: none;
        font-family: monospace;
        font-weight: bold;
        cursor: pointer;
        border-radius: 6px;
        color: #000;
    }
</style>

<div id="iptables-scene">
    <h2>INPUT Chain Traversal</h2>

<div class="chain-container">
        <div class="rule" id="rule1">
            <span>-p tcp --dport 22 (SSH)</span>
            <span id="status1"></span>
        </div>

<div class="rule" id="rule2">
            <span>-p tcp --dport 80 (HTTP)</span>
            <span id="status2"></span>
        </div>

<div class="action-box" id="actionBox">Default Policy: ACCEPT</div>
</div>

<div class="packet" id="packet">Packet → dport 80</div>

<div id="console"></div>

<button onclick="startAnimation()" id="btn">Start</button>

</div>

<script>
    function log(msg) {
        const consoleBox = document.getElementById("console");
        consoleBox.textContent += msg + "\n";
        consoleBox.scrollTop = consoleBox.scrollHeight;
    }

    function resetUI() {
        const packet = document.getElementById('packet');
        packet.style.transform = "translate(0,0)";
        packet.classList.remove("accepted");

        ["rule1","rule2"].forEach(id=>{
            const r = document.getElementById(id);
            r.classList.remove("matching","nomatch");
        });

        document.getElementById("status1").textContent = "";
        document.getElementById("status2").textContent = "";
        document.getElementById("actionBox").textContent = "Default Policy: ACCEPT";

        document.getElementById("console").textContent = "";
    }

    function startAnimation() {
        const btn = document.getElementById("btn");
        btn.textContent = "Running…";
        btn.disabled = true;

        resetUI();

        const packet = document.getElementById('packet');
        const rule1 = document.getElementById('rule1');
        const rule2 = document.getElementById('rule2');

        log("Starting packet traversal…");

        // Start animation
        setTimeout(() => {
            packet.style.transform = "translate(200px, 0)";
        }, 50);

        // Rule 1
        setTimeout(() => {
            rule1.classList.add("matching");
            log("Checking Rule 1: dport 22 → no match");
        }, 1200);

        setTimeout(() => {
            rule1.classList.remove("matching");
            rule1.classList.add("nomatch");
            packet.style.transform = "translate(200px, 70px)";
        }, 2200);

        // Rule 2
        setTimeout(() => {
            rule2.classList.add("matching");
            log("Checking Rule 2: dport 80 → MATCH (ACCEPT)");
        }, 3400);

        setTimeout(() => {
            rule2.classList.remove("matching");
            packet.classList.add("accepted");
            document.getElementById("actionBox").textContent = "ACTION: ACCEPT";
            packet.style.transform = "translate(200px, 140px)";
        }, 4500);

        // Exit
        setTimeout(() => {
            packet.style.transform = "translate(700px, 140px)";
            log("Traversal complete → ACCEPT");
        }, 5500);

        // Reset button
        setTimeout(() => {
            btn.textContent = "Run Again";
            btn.disabled = false;
        }, 6500);
    }
</script>

The way kube-proxy leverages `iptables` is by attaching rules to the `NAT PREROUTING` chain to implement its load balancing. This is quite simple and uses what is now a very mature kernel feature, working in tandem with the vast majority of networking infrastructure software that also rely on `iptables` for filtering (think CNIs, firewalls, etc).

However, the way kube-proxy is forced to program the `NAT PREROUTING` chain is suboptimal. Nominally, it is an O(n) operation to traverse the chain, where n is the number of rules in the chain. What's more, the chain grows linearly with the number of services (and subsequently the number of pods) in the cluster, leading to a linear increase in traversal time.

---

IPVS managed to evade the loss of its original name by its user-space utility, `ipvsadm`. It was merged relatively late into the Linux kernel, entering mainline in 2.4.x. Designed specifically for load balancing, IPVS maintains a conntrack-like table of virtual connections and uses standard load balancing scheduling algorithms, offering three forwarding modes: NAT, direct routing and tunneling.

When a packet is received at the interface where a virtual service (VIP:port) is configured, if it belongs to that connection, it is forwarded to the stored backend. Otherwise, it picks a backend based on the scheduling algorithm and creates a new connection entry in the conntrack table so future packets stay pinned.

<style>
    /* --- Layout --- */
    #ipvs-scene {
        font-family: monospace;
        padding: 25px;
        background-color: #0e0e0e;
        color: #a8ffbf;
        border: 1px solid #222;
        width: 760px;
        max-width: 100%;
        box-sizing: border-box;
        height: 460px;
        margin: 30px auto;
        position: relative;
        overflow: hidden;
        border-radius: 8px;
    }

    h2 {
        margin-top: 0;
        color: #fff;
        text-align: center;
        font-size: 22px;
        padding-bottom: 10px;
        border-bottom: 2px solid #333;
    }

    /* --- Director --- */
    .director-box {
        background: #17173a;
        border: 2px solid #5d5dff;
        width: 450px;
        margin: 15px auto;
        padding: 15px;
        border-radius: 8px;
        box-shadow: 0 0 12px #3434ff66;
        transition: background-color 0.5s, box-shadow 0.5s;
    }

    .director-box h3 {
        margin: 0 0 5px 0;
        color: #d1d1ff;
        font-size: 16px;
    }

    #decision-status {
        margin-top: 10px;
        height: 22px;
        color: #ff6b6b;
        font-weight: bold;
        font-size: 14px;
    }

    /* --- Real servers --- */
    .real-servers-container {
        margin-top: 35px;
        display: flex;
        justify-content: space-around;
        padding: 0 40px;
    }

    .real-server {
        width: 180px;
        height: 110px;
        background: #262626;
        border: 1px solid #555;
        border-radius: 6px;
        display: flex;
        flex-direction: column;
        justify-content: center;
        align-items: center;
        color: #e0e0e0;
        transition: background-color 0.4s, box-shadow 0.4s;
    }

    .real-server.processing {
        background: #0f401f;
        box-shadow: 0 0 12px #00ff6a;
    }

    /* --- Packet --- */
    .packet {
        position: absolute;
        top: 60px;
        left: -120px; /* Start off-screen */
        width: 120px;
        height: 35px;
        line-height: 35px;
        background: #ffb400;
        color: #000;
        font-weight: bold;
        text-align: center;
        border-radius: 5px;
        box-shadow: 0 0 10px #ffb400;
        transition: transform 1.5s ease-in-out,
                    background-color 0.5s,
                    box-shadow 0.5s,
                    opacity 0.5s;
        z-index: 10;
        opacity: 1;
    }

    .packet.routed {
        background-color: #00ff6a;
        box-shadow: 0 0 12px #00ff6a;
    }

    /* --- Controls --- */
    #start-status {
        text-align: center;
        margin-top: 10px;
        height: 20px;
        font-weight: bold;
        color: #ffae00;
        font-size: 14px;
    }

    button {
        position: absolute;
        bottom: 15px;
        left: 50%;
        transform: translateX(-50%);
        padding: 10px 26px;
        font-family: monospace;
        font-size: 14px;
        background-color: #00ff6a;
        color: #000;
        border: none;
        border-radius: 4px;
        cursor: pointer;
        font-weight: bold;
        box-shadow: 0 0 8px #00ff6a;
    }

    button:hover {
        filter: brightness(1.1);
    }
</style>

<div id="ipvs-scene">
    <h2>IPVS Load Balancing: Round Robin (RR)</h2>

<div class="director-box" id="director">
    <h3>LVS Director — VIP 192.168.1.10:80</h3>
    <p>Scheduler: Round Robin (RR)</p>
    <div id="decision-status"></div>
</div>

<div id="start-status"></div>

<div class="real-servers-container">
    <div class="real-server" id="rs1">
        <p>Real Server 1</p>
        <p>192.168.1.11</p>
    </div>
    <div class="real-server" id="rs2">
        <p>Real Server 2</p>
        <p>192.168.1.12</p>
    </div>
</div>

<div class="packet" id="packet">Client Request</div>
<button onclick="startAnimation()">Start Routing</button>
</div>

<script>
    let nextServer = 1;

    function startAnimation() {
        const packet     = document.getElementById('packet');
        const director   = document.getElementById('director');
        const rs1        = document.getElementById('rs1');
        const rs2        = document.getElementById('rs2');
        const status     = document.getElementById('decision-status');
        const startState = document.getElementById('start-status');

        /* --- Reset State --- */
        packet.style.transform = 'translate(0, 0)';
        packet.style.opacity = '1';
        packet.classList.remove('routed');
        rs1.classList.remove('processing');
        rs2.classList.remove('processing');
        director.style.boxShadow = "0 0 12px #3434ff66";
        director.style.backgroundColor = "#17173a";
        status.textContent = "";
        startState.textContent = "Routing started...";

        /* --- Animation Phases --- */

        /* Phase 1: Packet entering */
        setTimeout(() => {
            packet.style.transform = 'translate(200px, 0)';
        }, 80);

        /* Phase 2: VIP Lookup */
        setTimeout(() => {
            director.style.backgroundColor = "#3d3d8e";
            director.style.boxShadow = "0 0 14px #6666ff";
            status.textContent = "LOOKUP: VIP matched → Applying scheduler...";
        }, 1700);

        /* Phase 3: Decision */
        setTimeout(() => {
            status.textContent = `DECISION: Forward to Real Server ${nextServer}`;
            director.style.backgroundColor = "#17173a";
            director.style.boxShadow = "0 0 12px #3434ff66";
        }, 3300);

        /* Phase 4: Route Packet */
        setTimeout(() => {
            packet.classList.add("routed");

            const serverX = nextServer === 1 ? 160 : 530;
            const serverY = 260;

            packet.style.transform = `translate(${serverX}px, ${serverY}px)`;

            const target = document.getElementById(`rs${nextServer}`);
            target.classList.add("processing");
        }, 4800);

        /* Phase 5: Packet leaves */
        setTimeout(() => {
            packet.style.opacity = '0';
            packet.style.transform = `translate(${nextServer === 1 ? 160 : 530}px, 350px)`;
            nextServer = nextServer === 1 ? 2 : 1;
            startState.textContent = "Routing complete.";
        }, 6500);

        /* Cleanup for next run */
        setTimeout(() => {
            rs1.classList.remove("processing");
            rs2.classList.remove("processing");
            packet.style.opacity = "1";
        }, 7200);
    }
</script>

Rather than a list of sequential rules, it offers an optimized API and an optimized lookup routine. The result in kube-proxy is a nominal computation complexity of O(1). In most scenarios, its connection processing performance stays constant independent of the number of services in the cluster. One of the potential downsides if you're operating IPVS within a Kubernetes cluster is that it requires investigation as to whether it will behave as expected together with tools that rely on `iptables` packet filtering.

### In the wild

So, nominally kube-proxy's connection processing performance is better in IPVS mode than in iptables mode. In practice, there are two key attributes you will likely care about when it comes to the performance of kube-proxy:

- CPU usage: how does your host where your pods are scheduled perform, including userspace and kernel/system usage, across all the processes needed to support your microservices stack, including kube-proxy?
- Round-trip time: when your microservices call each other, how long does it take on average for the to send and receive requests and responses?

The best way to test this is launch a load generator client microservice pod on a dedicated node generating around 1000 requests per second to a Kubernetes service backend. Scaling up to 100,000 service backends and running the load tests on repeat, I was able to paint a picture of the performance of kube-proxy both in IPVS and iptables mode.

<style>
    #benchmark-scene {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        padding: 32px;
        background: #f5f5f7;
        border: 1px solid #d0d0d0;
        color: #222;
        width: 860px;
        max-width: 100%;
        box-sizing: border-box;
        margin: 30px auto;
        border-radius: 12px;
        box-shadow: 0 6px 20px rgba(0,0,0,0.08);
    }

    h2 {
        text-align: center;
        color: #0b57d0;
        margin-bottom: 18px;
        font-weight: 600;
        letter-spacing: -0.3px;
    }

    .controls {
        text-align: center;
        margin-bottom: 35px;
        padding: 18px;
        border: 1px solid #ccc;
        border-radius: 8px;
        background-color: #fff;
    }

    .controls label {
        font-size: 1.05em;
        font-weight: 600;
        margin-right: 10px;
    }
    .controls output {
        font-size: 1.05em;
        font-weight: 700;
        margin-left: 10px;
    }

    input[type="range"] {
        width: 520px;
        margin-top: 8px;
    }

    .comparison-container {
        display: flex;
        justify-content: space-between;
        text-align: center;
        gap: 24px;
    }

    .mode-panel {
        flex: 1;
        padding: 26px;
        border-radius: 10px;
        min-height: 280px;
        position: relative;
        background-color: #fff;
        box-shadow: 0 2px 8px rgba(0,0,0,0.06);
    }

    .iptables-mode { border-top: 6px solid #d93025; }
    .ipvs-mode     { border-top: 6px solid #188038; }

    .mode-panel h3 {
        margin-bottom: 8px;
        font-size: 1.25em;
        font-weight: 600;
    }

    .description {
        font-size: 0.9em;
        color: #555;
        margin-bottom: 18px;
        min-height: 36px;
        padding: 0 4px;
    }

    .latency-bar-container {
        height: 170px;
        width: 100%;
        display: flex;
        align-items: flex-end;
        justify-content: center;
        margin-top: 10px;
    }

    .latency-bar {
        width: 85px;
        background-color: #ccc;
        transition: height 0.35s ease-out, background-color 0.45s, transform 0.45s;
        border-radius: 4px 4px 0 0;
        display: flex;
        align-items: flex-start;
        justify-content: center;
        font-size: 0.85em;
        font-weight: 700;
        color: #222;
        position: relative;
        transform-origin: bottom;
    }

    .latency-value {
        position: absolute;
        top: -24px;
        font-size: 0.95em;
        font-weight: 600;
        color: #222;
    }
</style>

<div id="benchmark-scene">
  <h2>Kubernetes Service Routing Performance at Scale</h2>

  <div class="controls">
    <label for="service-slider">Number of Services:</label>
    <input
      type="range"
      id="service-slider"
      min="10"
      max="20000"
      step="10"
      value="1000"
      oninput="updateAnimation()"
    />
    <output id="service-count">1000</output>
    <p style="font-size: 0.9em; margin-top: 6px;">
      10 endpoints per service • 1000 rps per client node
    </p>
  </div>

  <div class="comparison-container">
    <div class="mode-panel iptables-mode">
      <h3>IPTABLES Mode</h3>
      <div class="description">
        Sequential rule chain evaluation. Cost grows with every additional service.
      </div>
      <div class="latency-bar-container">
        <div class="latency-bar" id="iptables-bar">
          <span class="latency-value" id="iptables-latency"></span>
        </div>
      </div>
    </div>

    <div class="mode-panel ipvs-mode">
      <h3>IPVS Mode</h3>
      <div class="description">
        Constant-time lookup through hashed connection tables.
      </div>
      <div class="latency-bar-container">
        <div class="latency-bar" id="ipvs-bar">
          <span class="latency-value" id="ipvs-latency"></span>
        </div>
      </div>
    </div>

  </div>
</div>

<script>
    const BASE_LATENCY = 8;

    function calculateIptablesLatency(N) {
        return BASE_LATENCY + (0.006 * Math.pow(N, 1.07));
    }

    function calculateIpvsLatency(N) {
        return BASE_LATENCY + (0.00008 * N);
    }

    function getBarHeight(latency, maxLatency) {
        const MAX_HEIGHT = 170;
        return Math.min(MAX_HEIGHT, (latency / maxLatency) * MAX_HEIGHT);
    }

    function getBarColor(latency) {
        if (latency < 20) return '#4CAF50';
        if (latency < 50) return '#F9C400';
        if (latency < 100) return '#FB8C00';
        return '#E53935';
    }

    function animateValue(el, value) {
        el.textContent = value.toFixed(2) + " ms";
    }

    function updateAnimation() {
        const N = parseInt(document.getElementById('service-slider').value);
        document.getElementById('service-count').value = N.toLocaleString();

        const iptLatency = calculateIptablesLatency(N);
        const ipvsLatency = calculateIpvsLatency(N);

        const MAX = 80;

        const iptBar = document.getElementById('iptables-bar');
        const ipvsBar = document.getElementById('ipvs-bar');

        iptBar.style.height = getBarHeight(iptLatency, MAX) + "px";
        iptBar.style.backgroundColor = getBarColor(iptLatency);
        animateValue(document.getElementById('iptables-latency'), iptLatency);

        ipvsBar.style.height = getBarHeight(ipvsLatency, MAX) + "px";
        ipvsBar.style.backgroundColor = getBarColor(ipvsLatency);
        animateValue(document.getElementById('ipvs-latency'), ipvsLatency);
    }

    document.addEventListener('DOMContentLoaded', updateAnimation);
</script>

When considering round-trip response time it's important to note that the difference between connections and requests is persistency. Most of the time, microservices will use "keepalive" connections, where each connection is reused for multiple requests. This is important because most new connections require a three-way handshake (SYN, SYN-ACK, ACK), which in turn requires more processing within the kernel networking stack.

Nginx is everyone's goto for simulating networking applications so we used it and its default keepalive configuration to get a ratio of round-trip response time vs number of connections. The default max keepalive connections is 100, so we used that as our upper bound.

<style>
    #keepalive-scene {
        font-family: monospace;
        padding: 25px;
        background-color: #1e1e1e;
        color: #e8e8e8;
        border: 1px solid #444;
        width: 760px;
        max-width: 100%;
        box-sizing: border-box;
        height: 380px;
        margin: 30px auto;
        position: relative;
        border-radius: 8px;
        overflow: hidden;
    }
    #keepalive-scene h2 {
        text-align: center;
        margin-top: 0;
        color: #4da6ff;
        font-size: 20px;
        border-bottom: 1px solid #333;
        padding-bottom: 10px;
    }
    .endpoint {
        position: absolute;
        width: 120px;
        height: 80px;
        background: #2a2a2a;
        border: 2px solid #555;
        border-radius: 6px;
        display: flex;
        justify-content: center;
        align-items: center;
        font-weight: bold;
    }
    #client-node { top: 120px; left: 40px; border-color: #4da6ff; }
    #server-node { top: 120px; right: 40px; border-color: #ff4d4d; }
    .packet-ka {
        position: absolute;
        width: 80px;
        height: 24px;
        background: #4da6ff;
        color: #000;
        text-align: center;
        line-height: 24px;
        font-size: 12px;
        font-weight: bold;
        border-radius: 12px;
        top: 148px;
        left: 170px;
        opacity: 0;
        transition: transform 1s linear, opacity 0.2s;
    }
    .syn-packet { background: #ffcc00; }
    .data-packet { background: #4da6ff; }
    #connection-line {
        position: absolute;
        top: 158px;
        left: 170px;
        width: 420px;
        height: 4px;
        background: #333;
        z-index: 0;
    }
    #connection-line.established {
        background: #4da6ff;
        box-shadow: 0 0 8px #4da6ff;
    }
    .log-panel {
        position: absolute;
        bottom: 20px;
        left: 40px;
        right: 40px;
        height: 80px;
        background: #000;
        border: 1px solid #333;
        padding: 10px;
        font-size: 12px;
        overflow-y: auto;
        border-radius: 4px;
    }
    .ka-controls {
        position: absolute;
        bottom: 120px;
        left: 50%;
        transform: translateX(-50%);
        display: flex;
        gap: 15px;
    }
    .ka-btn {
        padding: 8px 16px;
        background: #333;
        color: #fff;
        border: 1px solid #555;
        border-radius: 4px;
        cursor: pointer;
        font-family: monospace;
    }
    .ka-btn:hover { background: #444; }
</style>

<div id="keepalive-scene">
    <h2>Connection Overhead: Keepalive vs New</h2>
    <div id="connection-line"></div>
    <div id="client-node" class="endpoint">Client</div>
    <div id="server-node" class="endpoint">Server</div>

    <div id="p-syn" class="packet-ka syn-packet">SYN</div>
    <div id="p-synack" class="packet-ka syn-packet">SYN-ACK</div>
    <div id="p-ack" class="packet-ka syn-packet">ACK</div>
    <div id="p-data1" class="packet-ka data-packet">REQ 1</div>
    <div id="p-resp1" class="packet-ka data-packet">RESP 1</div>
    <div id="p-data2" class="packet-ka data-packet">REQ 2</div>
    <div id="p-resp2" class="packet-ka data-packet">RESP 2</div>

    <div class="ka-controls">
        <button class="ka-btn" onclick="runWithoutKeepalive()">No Keepalive</button>
        <button class="ka-btn" onclick="runWithKeepalive()">With Keepalive</button>
    </div>
    <div class="log-panel" id="ka-log"> Waiting to start...</div>

</div>

<script>
    function kaLog(msg) {
        const logger = document.getElementById("ka-log");
        logger.innerHTML += "<div>> " + msg + "</div>";
        logger.scrollTop = logger.scrollHeight;
    }

    function resetKA() {
        document.getElementById("ka-log").innerHTML = "";
        document.getElementById("connection-line").classList.remove("established");
        document.querySelectorAll(".packet-ka").forEach(p => {
            p.style.transition = "none";
            p.style.opacity = "0";
            p.style.transform = "translateX(0)";
        });
    }

    function animatePacket(id, delay, fromRight) {
        return new Promise(resolve => {
            setTimeout(() => {
                const p = document.getElementById(id);
                p.style.transition = "none";
                p.style.opacity = "1";
                p.style.transform = fromRight ? "translateX(340px)" : "translateX(0)";

                setTimeout(() => {
                    p.style.transition = "transform 0.8s linear, opacity 0.2s";
                    p.style.transform = fromRight ? "translateX(0)" : "translateX(340px)";
                }, 50);

                setTimeout(() => {
                    p.style.opacity = "0";
                    resolve();
                }, 900);
            }, delay);
        });
    }

    async function runWithoutKeepalive() {
        resetKA();
        kaLog("Starting standard connection (No Keepalive)");
        // Req 1
        kaLog("Initiating TCP 3-way handshake...");
        await animatePacket("p-syn", 0, false);
        await animatePacket("p-synack", 0, true);
        await animatePacket("p-ack", 0, false);
        document.getElementById("connection-line").classList.add("established");
        kaLog("Connection established. Sending Request 1.");
        await animatePacket("p-data1", 0, false);
        await animatePacket("p-resp1", 0, true);
        document.getElementById("connection-line").classList.remove("established");
        kaLog("Connection closed. (Delay overhead)");

        // Req 2
        setTimeout(async () => {
            kaLog("Initiating new TCP 3-way handshake for Request 2...");
            await animatePacket("p-syn", 0, false);
            await animatePacket("p-synack", 0, true);
            await animatePacket("p-ack", 0, false);
            document.getElementById("connection-line").classList.add("established");
            kaLog("Connection established. Sending Request 2.");
            await animatePacket("p-data2", 0, false);
            await animatePacket("p-resp2", 0, true);
            document.getElementById("connection-line").classList.remove("established");
            kaLog("Done. High latency overhead observed.");
        }, 1000);
    }

    async function runWithKeepalive() {
        resetKA();
        kaLog("Starting Keepalive connection...");
        kaLog("Initiating TCP 3-way handshake...");
        await animatePacket("p-syn", 0, false);
        await animatePacket("p-synack", 0, true);
        await animatePacket("p-ack", 0, false);
        document.getElementById("connection-line").classList.add("established");
        kaLog("Connection established. Sending Request 1.");
        await animatePacket("p-data1", 0, false);
        await animatePacket("p-resp1", 0, true);
        kaLog("Connection kept alive. Sending Request 2 immediately.");
        await animatePacket("p-data2", 0, false);
        await animatePacket("p-resp2", 0, true);
        kaLog("Done. Minimal latency, fast processing.");
    }
</script>

As you can see, negotiating a new connection every time severely penalizes your response times. The more services you have scaling up, the more connections are dropping and reforming.

### Why Keepalive Matters (skip if you are overly familiar with TCP)

To understand this overhead, we have to distinguish between a _request_ and a _connection_. When a client (like another microservice) wants to talk to a backend, it first has to establish a TCP connection via a three-way handshake:

1. **SYN**: Client asks to sync.
2. **SYN-ACK**: Server acknowledges and asks to sync back.
3. **ACK**: Client acknowledges the server.

Only _after_ this dance can the actual HTTP data be transmitted. If we close the connection after every single request, we pay this 3-way latency tax over and over again. By utilizing HTTP `Keep-Alive` (or persistent connections), a single TCP connection is kept open and reused for multiple subsequent requests. In the context of `kube-proxy`, `iptables` needs to evaluate rules for _new_ connections. Once a connection is established, Netfilter's `conntrack` (connection tracking) module remembers it, and subsequent packets for that connection bypass the heavy rule traversal. This means if your microservices are properly pooling and keeping connections alive, the theoretical O(n) penalty of `iptables` is paid far less frequently than you might think.

### `iptables` bottleneck math

We have a mechanism in `IPVS` that clearly boasts superior lookup mathematics (O(1) vs O(n)). If it were a problem of mathematics (and in computing, surprisingly, it's not always the case), we'd be looking at a cluster with 1,000 to 5,000 services before we'd see a real issue. And, the choice for a network layer would be as simple as comparing two numbers.

In computer science, **O(n)** means the time taken grows linearly with the number of items. For `iptables`, `n` is the number of services (and their associated endpoints). If you have 10 services, traversing the rule chain is instantaneous. If you have 10,000 services, `kube-proxy` has programmed tens of thousands of iptables rules. When a new packet arrives, the Linux kernel must potentially evaluate it against _all_ of those rules sequentially until it finds a match.

**O(1)**, on the other hand, means constant time. No matter if you have 10 services or 100,000, `IPVS` uses a hash table to find the correct backend route instantly in a single mathematical step.

If you remember from earlier, a statistically typical cluster holds only a handful of nodes and realistically less than 1,000 services. The fact of the matter is that `iptables` processing only truly starts failing the latency sniff test once you surpass the 1,000 to 5,000 service mark. Below those numbers, the CPU processing difference between O(n) and O(1) in the kernel is practically unnoticeable in the face of network I/O overhead. We are debating over single-digit millisecond or even microsecond latency differences.

### What if you didn't have to choose?

Even when you are facing those massive cluster topologies where the O(n) math becomes a real bottleneck, replacing `kube-proxy`'s backend with `IPVS` isn't the magic wand infrastructure people want. But, not to say that there isn't one.

eBPF is an interesting kernel runtime that allows you to run sandboxed programs directly within the Linux kernel space without having to change kernel source code or load kernel modules. Instead of relying on the Netfilter stack to process packets at the network layer, eBPF allows tools like **Cilium** to attach routing logic directly to the socket layer or early in the network interface controller (NIC) packet pipeline.

To put it simply, networking, and specifically in Kubernetes, can be thought of as a mail sorting system inside a city. When traffic comes into a cluster, something has to decide which pod should receive it. Traditionally, this job is done by the Netfilter stack via `kube-proxy`. With `eBPF`, instead of relying on an external application, a program is attached to the kernel that can make routing decisions directly on the packet level.

By the time a packet even reaches the Netfilter stack where `iptables` and `IPVS` live, eBPF has already routed it directly to the correct pod. It radically bypasses the entire traditional networking stack, blowing the performance and observability of both IPVS and iptables completely out of the water.

<style>
    #ebpf-scene {
        font-family: monospace;
        padding: 25px;
        background-color: #1a1b26;
        color: #a9b1d6;
        border: 1px solid #414868;
        width: 760px;
        max-width: 100%;
        box-sizing: border-box;
        height: 480px;
        margin: 30px auto;
        position: relative;
        border-radius: 8px;
        overflow: hidden;
    }
    #ebpf-scene h2 {
        text-align: center;
        margin-top: 0;
        color: #7aa2f7;
        font-size: 20px;
        border-bottom: 1px solid #414868;
        padding-bottom: 10px;
    }
    .ebpf-node {
        position: absolute;
        border-radius: 6px;
        display: flex;
        justify-content: center;
        align-items: center;
        font-weight: bold;
        text-align: center;
        padding: 10px;
        box-shadow: 0 4px 6px rgba(0,0,0,0.3);
    }
    #nic-node {
        width: 120px; height: 60px;
        background: #24283b; border: 2px solid #565f89;
        bottom: 60px; left: 320px;
    }
    #kernel-box {
        position: absolute;
        top: 100px; left: 40px; right: 40px; height: 220px;
        border: 2px dashed #414868;
        border-radius: 8px;
        background: #1f2335;
        z-index: 1;
    }
    .kernel-label {
        position: absolute; top: 10px; left: 15px; color: #565f89; font-weight: bold;
    }
    #netfilter-node {
        width: 140px; height: 80px;
        background: #f7768e; color: #1a1b26;
        top: 130px; left: 80px;
        z-index: 2;
    }
    #ebpf-node {
        width: 140px; height: 80px;
        background: #9ece6a; color: #1a1b26;
        top: 220px; right: 260px;
        z-index: 2;
    }
    #pod-node {
        width: 120px; height: 60px;
        background: #7aa2f7; color: #1a1b26;
        top: 20px; right: 80px;
        z-index: 2;
    }
    .ebpf-packet {
        position: absolute;
        width: 60px; height: 30px;
        background: #e0af68; color: #1a1b26;
        border-radius: 15px;
        text-align: center; line-height: 30px; font-weight: bold; font-size: 12px;
        left: 350px; bottom: 130px; /* Right above NIC */
        opacity: 0;
        z-index: 10;
        transition: transform 1s ease-in-out, opacity 0.2s;
    }
    .ebpf-controls {
        position: absolute;
        bottom: 20px; left: 20px; right: 20px;
        display: flex; justify-content: space-between;
    }
    .ebpf-btn {
        padding: 8px 16px; background: #24283b; color: #a9b1d6;
        border: 1px solid #565f89; border-radius: 4px; cursor: pointer; font-family: inherit; font-weight: bold;
    }
    .ebpf-btn:hover { background: #414868; }
    .ebpf-status {
        flex-grow: 1; text-align: center; line-height: 35px; color: #ff9e64; font-weight: bold;
    }
</style>

<div id="ebpf-scene">
    <h2>Packet Routing: Netfilter vs eBPF</h2>

    <div id="kernel-box">
        <div class="kernel-label">Kernel Space</div>
    </div>

    <div id="nic-node" class="ebpf-node">Network Intf<br>(NIC)</div>
    <div id="netfilter-node" class="ebpf-node">Netfilter Stack<br>(iptables/IPVS)</div>
    <div id="ebpf-node" class="ebpf-node">eBPF Hook<br>(e.g. Cilium)</div>
    <div id="pod-node" class="ebpf-node">Target Pod</div>

    <div id="e-packet" class="ebpf-packet">DATA</div>

    <div class="ebpf-controls">
        <button class="ebpf-btn" onclick="runTraditional()">Traditional</button>
        <div id="ebpf-status" class="ebpf-status">Awaiting routing selection...</div>
        <button class="ebpf-btn" onclick="runeBPF()">eBPF Fast Path</button>
    </div>

</div>

<script>
    function resetEBPF() {
        const p = document.getElementById("e-packet");
        p.style.transition = "none";
        p.style.opacity = "0";
        p.style.transform = "translate(0, 0)";

        document.getElementById("netfilter-node").style.boxShadow = "0 4px 6px rgba(0,0,0,0.3)";
        document.getElementById("ebpf-node").style.boxShadow = "0 4px 6px rgba(0,0,0,0.3)";
    }

    function setStatus(msg, color) {
        const s = document.getElementById("ebpf-status");
        s.textContent = msg;
        s.style.color = color;
    }

    function runTraditional() {
        resetEBPF();
        setStatus("1. Packet arrives at NIC", "#a9b1d6");
        const p = document.getElementById("e-packet");

        setTimeout(() => {
            p.style.opacity = "1";
            p.style.transition = "transform 0.8s ease-in-out";

            p.style.transform = "translate(-230px, -165px)";
            setStatus("2. Traverses Kernel to Netfilter stack", "#f7768e");

            setTimeout(() => {
                document.getElementById("netfilter-node").style.boxShadow = "0 0 15px #f7768e";
                setStatus("3. iptables/IPVS evaluates routing rules", "#f7768e");

                setTimeout(() => {
                    document.getElementById("netfilter-node").style.boxShadow = "0 4px 6px rgba(0,0,0,0.3)";
                    p.style.transform = "translate(240px, -300px)";
                    setStatus("4. Forwarded to Target Pod", "#7aa2f7");

                    setTimeout(() => {
                        p.style.opacity = "0";
                        setStatus("Traditional routing complete", "#a9b1d6");
                    }, 800);
                }, 1200);
            }, 800);
        }, 100);
    }

    function runeBPF() {
        resetEBPF();
        setStatus("1. Packet arrives at NIC", "#a9b1d6");
        const p = document.getElementById("e-packet");

        setTimeout(() => {
            p.style.opacity = "1";
            p.style.transition = "transform 0.5s ease-in-out";

            p.style.transform = "translate(40px, -70px)";
            setStatus("2. eBPF Hook intercepts early!", "#9ece6a");

            setTimeout(() => {
                document.getElementById("ebpf-node").style.boxShadow = "0 0 15px #9ece6a";
                setStatus("3. eBPF routing decision made instantly", "#9ece6a");

                setTimeout(() => {
                    document.getElementById("ebpf-node").style.boxShadow = "0 4px 6px rgba(0,0,0,0.3)";
                    p.style.transition = "transform 0.7s ease-in-out";
                    p.style.transform = "translate(240px, -300px)";
                    setStatus("4. Bypasses Netfilter directly to Pod", "#7aa2f7");

                    setTimeout(() => {
                        p.style.opacity = "0";
                        setStatus("eBPF fast path complete", "#a9b1d6");
                    }, 700);
                }, 800);
            }, 500);
        }, 100);
    }
</script>

### The 1% problem

Essentially, the deprecation of `iptables` in favor of more advanced implementations like `IPVS` or eBPF proxies feels like it was designed to cater to the top 1% of Kubernetes users—the hyperscalers, the massive multi-tenant SaaS providers, and the heavily fragmented microservice jungles. For the vast, overwhelming majority of teams running a dozen or so services on a 5-node cluster, migrating the networking layer brings absolutely no tangible real-world benefit and simply adds operational complexity to a stack that is already a jigsaw puzzle blindfolded.

But, if your workload is small enough that the algorithmic complexity of sequential IP filtering is completely irrelevant to you... should you even be running Kubernetes at all?

But I think we'll leave that philosophical crisis for another day.
