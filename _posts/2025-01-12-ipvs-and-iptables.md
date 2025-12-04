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
    #iptables-scene {
            font-family: monospace;
            padding: 20px;
            border: 1px solid #333;
            background-color: #1e1e1e;
            color: #00ff41;
            overflow: hidden;
            position: relative;
            width: 600px;
            height: 350px;
            margin: 20px auto;
        }
        h2 {
            text-align: center;
            color: #fff;
            margin-top: 0;
        }
        .chain-container {
            position: absolute;
            top: 60px;
            left: 20px;
            width: 560px;
        }
        .rule {
            background: #333;
            border: 1px solid #555;
            padding: 10px;
            margin-bottom: 5px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            height: 40px;
            transition: background-color 0.3s;
        }
        .match-criteria {
            margin: 0;
            font-size: 0.9em;
        }
        .status {
            width: 100px;
            text-align: right;
            font-weight: bold;
            color: #fff;
        }
        .action-box {
            background: #444;
            padding: 10px;
            text-align: center;
            border: 2px dashed #00ff41;
            margin-top: 10px;
            height: 30px;
            line-height: 30px;
        }
        .packet {
            position: absolute;
            top: 80px;
            left: -100px; /* Start off-screen */
            width: 120px;
            height: 30px;
            line-height: 30px;
            background: #007bff;
            color: white;
            text-align: center;
            border-radius: 5px;
            transition: transform 1.5s ease-in-out, background-color 0.5s;
            z-index: 10;
            box-shadow: 0 0 10px #007bff;
        }
        button {
            position: absolute;
            bottom: 10px;
            left: 50%;
            transform: translateX(-50%);
            padding: 10px 20px;
            background-color: #00ff41;
            border: none;
            cursor: pointer;
            font-family: monospace;
            font-weight: bold;
        }
        /* Specific state colors */
        .no-match {
            background-color: #700;
        }
        .match-found {
            background-color: #070;
        }
        .accepted {
            background-color: #0c0;
            box-shadow: 0 0 10px #0c0;
        }
        .dropped {
            background-color: #a00;
            box-shadow: 0 0 10px #a00;
        }
    </style>

<div id="iptables-scene">
    <h2>INPUT Chain Traversal</h2>
    <div class="chain-container">
        <div class="rule-1 rule">
            <p class="match-criteria">Rule 1: -p tcp --dport 22 (SSH)</p>
            <div class="status" id="status-1"></div>
        </div>
        <div class="rule-2 rule">
            <p class="match-criteria">Rule 2: -p tcp --dport 80 (HTTP)</p>
            <div class="status" id="status-2"></div>
        </div>
        <div class="action-box" id="accept-target">Default Policy: ACCEPT</div>
    </div>
    <div class="packet" id="packet">Packet (Dest: 80)</div>
    <button onclick="startAnimation()">Run Packet</button>
</div>


<script>
    function startAnimation() {
        const packet = document.getElementById('packet');
        const rule1 = document.querySelector('.rule-1');
        const rule2 = document.querySelector('.rule-2');
        const status1 = document.getElementById('status-1');
        const status2 = document.getElementById('status-2');
        const actionBox = document.getElementById('accept-target');

        packet.style.transform = 'translate(0, 0)';
        packet.classList.remove('accepted', 'dropped');
        packet.style.transitionDuration = '1.5s'; 
        rule1.classList.remove('no-match', 'match-found');
        rule2.classList.remove('no-match', 'match-found');
        status1.textContent = '';
        status2.textContent = '';
        actionBox.textContent = 'Default Policy: ACCEPT';



        setTimeout(() => {
            packet.style.transform = 'translate(150px, 0)'; 
        }, 50); 

        setTimeout(() => {
            rule1.classList.add('no-match');
            status1.textContent = 'NO MATCH';
        }, 1600);

        setTimeout(() => {
            packet.style.transform = 'translate(150px, 50px)';
            rule1.classList.remove('no-match');
        }, 3200);

        setTimeout(() => {
            rule2.classList.add('match-found');
            status2.textContent = 'MATCH! Target: ACCEPT';
        }, 4800);

        setTimeout(() => {
            packet.style.transform = 'translate(150px, 110px)';
            packet.classList.add('accepted');
            actionBox.textContent = 'ACTION TAKEN: ACCEPT';
            rule2.classList.remove('match-found');
        }, 6400);

        setTimeout(() => {
            packet.style.transitionDuration = '0.5s'; 
            packet.style.transform = 'translate(700px, 110px)';
        }, 8000);
    }

</script>

The way kube-proxy leverages `iptables` is by attaching rules to the `NAT PREROUTING` chain to implement its load balancing. This is quite simple and uses what is now a very mature kernel feature, working in tandem with the vast majority of networking infrastructure software that also rely on `iptables` for filtering (think CNIs, firewalls, etc).

However, the way kube-proxy is forced to program the `NAT PREROUTING` chain is suboptimal. Nominally, it is an O(n) operation to traverse the chain, where n is the number of rules in the chain. What's more, the chain grows linearly with the number of services (and subsequently the number of pods) in the cluster, leading to a linear increase in traversal time. 

---
IPVS managed to evade the loss of its original name by its user-space utility, `ipvsadm`. It was merged relatively late into the Linux kernel, entering mainline in 2.4.x. Designed specifically for load balancing, IPVS maintains a conntrack-like table of virtual connections and uses standard load balancing scheduling algorithms, offering three forwarding modes: NAT, direct routing and tunneling.

When a packet is received at the interface where a virtual service (VIP:port) is configured, if it belongs to that connection, it is forwarded to the stored backend. Otherwise, it picks a backend based on the scheduling algorithm and creates a new connection entry in the conntrack table so future packets stay pinned.

<style>
        /* CSS is included here for simplicity */
        #ipvs-scene {
            font-family: monospace;
            padding: 20px;
            border: 1px solid #333;
            background-color: #1e1e1e;
            color: #00ff41;
            overflow: hidden;
            position: relative;
            width: 700px;
            height: 400px;
            margin: 20px auto;
            text-align: center;
        }
        h2 {
            color: #fff;
            margin-top: 0;
            border-bottom: 2px solid #555;
            padding-bottom: 10px;
        }
        .director-box {
            position: relative;
            margin: 20px auto;
            width: 400px;
            padding: 15px;
            background: #2a2a5c; /* IPVS Director color */
            border: 2px solid #4d4dff;
            box-shadow: 0 0 15px #4d4dff;
            color: white;
            transition: background-color 0.5s;
        }
        .director-box h3 {
            margin: 0 0 5px 0;
        }
        .real-servers-container {
            display: flex;
            justify-content: space-around;
            margin-top: 40px;
        }
        .real-server {
            width: 150px;
            height: 100px;
            padding: 10px;
            background: #333;
            border: 1px solid #777;
            color: #fff;
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            transition: background-color 0.5s, box-shadow 0.5s;
        }
        .packet {
            position: absolute;
            top: 50px;
            left: -100px; /* Start off-screen */
            width: 100px;
            height: 30px;
            line-height: 30px;
            background: #ffaa00; /* Incoming color */
            color: black;
            font-weight: bold;
            text-align: center;
            border-radius: 5px;
            transition: transform 1.5s ease-in-out, background-color 0.5s, box-shadow 0.5s;
            z-index: 10;
        }
        .routed {
            background-color: #00ff41; /* Routed color */
        }
        .processing {
            background-color: #007700;
            box-shadow: 0 0 15px #00ff41;
        }
        
        button {
            position: absolute;
            bottom: 10px;
            left: 50%;
            transform: translateX(-50%);
            padding: 10px 20px;
            background-color: #00ff41;
            border: none;
            cursor: pointer;
            font-family: monospace;
            font-weight: bold;
        }
    </style>


<div id="ipvs-scene">
    <h2>IPVS Load Balancing: Round Robin (RR)</h2>
    
<div class="director-box" id="director">
    <h3>LVS Director (VIP: 192.168.1.10:80)</h3>
    <p>Scheduler: Round Robin (RR)</p>
    <div id="decision-status" style="height: 20px; color: #ff0000; font-weight: bold;"></div>
</div>
    
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
<button onclick="startAnimation()">Start IPVS Routing</button>
</div>

<script>
    // JavaScript is included here for simplicity
    
    // We maintain a global state for the Round Robin logic
    let nextServer = 1; 

    function startAnimation() {
        const packet = document.getElementById('packet');
        const director = document.getElementById('director');
        const rs1 = document.getElementById('rs1');
        const rs2 = document.getElementById('rs2');
        const decisionStatus = document.getElementById('decision-status');
        
        // Reset state
        packet.style.transform = 'translate(0, 0)';
        packet.classList.remove('routed');
        rs1.classList.remove('processing');
        rs2.classList.remove('processing');
        decisionStatus.textContent = '';
        director.style.backgroundColor = '#2a2a5c';

        // --- Animation Steps ---

        // 1. Packet enters Director's vicinity
        setTimeout(() => {
            packet.style.transform = 'translate(150px, 0)'; 
        }, 50); 

        // 2. Director performs lookup and scheduling
        setTimeout(() => {
            director.style.backgroundColor = '#4d4dff'; // Flash Director
            decisionStatus.textContent = 'LOOKUP: VIP matched. SCHEDULER: Round Robin...';
        }, 1600);

        // 3. Routing Decision made
        setTimeout(() => {
            decisionStatus.textContent = `ROUTE DECISION: Real Server ${nextServer}`;
            director.style.backgroundColor = '#2a2a5c'; 
        }, 3200);

        // 4. Packet is routed to the selected Real Server
        setTimeout(() => {
            packet.classList.add('routed');
            
            let rsYOffset = 210; 
            let rsXOffset = nextServer === 1 ? 150 : 410; // Position above RS1 or RS2
            
            packet.style.transform = `translate(${rsXOffset}px, ${rsYOffset}px)`;

            // Get the target RS element and mark it as processing
            const targetRS = document.getElementById(`rs${nextServer}`);
            targetRS.classList.add('processing');

        }, 4800);
        
        // 5. Connection processed (Packet removed)
        setTimeout(() => {
            packet.style.transform = `translate(${nextServer === 1 ? 50 : 510}px, 300px)`; // Move packet out
            packet.style.opacity = '0'; // Fade out
            
            // Advance the Round Robin counter
            nextServer = nextServer === 1 ? 2 : 1; 
        }, 6400);
        
        // 6. Reset visual state of the server
        setTimeout(() => {
             rs1.classList.remove('processing');
             rs2.classList.remove('processing');
             packet.style.opacity = '1';
        }, 7000);
    }
</script>

Rather than a list of sequential rules, it offers an optimized API and an optimized lookup routine. The result in kube-proxy is a nominal computation complexity of O(1). In most scenarios, its connection processing performance stays constant independent of the number of services in the cluster. One of the potential downsides if you're operating IPVS within a Kubernetes cluster is that it requires investigation as to whether it will behave as expected together with tools that rely on `iptables` packet filtering. 

### In the wild

So, nominally kube-proxy's connection processing performance is better in IPVS mode than in iptables mode. In practice, there are two key attributes you will likely care about when it comes to the performance of kube-proxy: 

- CPU usage: how does your host where your pods are scheduled perform, including userspace and kernel/system usage, across all the processes needed to support your microservices stack, including kube-proxy?
- Round-trip time: when your microservices call each other, how long does it take on average for the to send and receive requests and responses?

The best way to test this is launch a load generator client microservice pod on a dedicated node generating around 1000 requests per second to a Kubernetes service backend. Scaling up to 100,000 service backends and running the load tests on repeat, I was able to paint a picture of the performance of kube-proxy both in IPVS and iptables mode. 

