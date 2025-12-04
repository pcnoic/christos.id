---
layout: post
title: Exotic networking patterns for load balancing that you probably don't need 
date: 2025-01-12
preview: true
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
        margin: 30px auto;
        border-radius: 10px;
        position: relative;
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

