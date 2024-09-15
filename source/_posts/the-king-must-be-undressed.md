---
title: The undressing of the king
---

## For the last two decades Amazon, Microsoft, Google and Alibaba have been amassing the world's compute. Now they own 67% of it. If we are to build knock-off humans, where do we go from here?

People are trying to build humans. Some are trying their luck with tubes, while others are more interested in the amalgamation of software and hardware. Regardless, both need a lot of compute. 

According to OpenAI's calculations, training GPT-3, the first model to achieve some sense of superiority in conversational scenarios, required 314 exaFLOPs. [LLaMA](https://arxiv.org/pdf/2302.13971.pdf) was trained on a cluster of 2048 A100s, with ~312 TFLOPS each. 2048 is currently the most A100s that can work together on a model due to the switch topology.

That cluster is giving out 639 PFLOPS. 

[![](https://substackcdn.com/image/fetch/w_1456,c_limit,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F8bbb56c1-ca66-4c5f-88bf-6c8fe0d43e64_1280x720.webp)](https://substackcdn.com/image/fetch/f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F8bbb56c1-ca66-4c5f-88bf-6c8fe0d43e64_1280x720.webp)

This scale of computing signifies not just technological advancement but an escalating barrier to entry in AI research and development. 

Consider the concept of computer scaling in terms of its advancement beyond the capabilities of a standard desktop computer. Currently, a typical desktop operates at approximately 50 TFLOPS. This performance can be humorously compared to a "mouse of compute," symbolically representing one 400th of a computational "person" or an additional nine iterations of Moore's Law awaiting realization. I project the advent of the technological Singularity around 2038, coincidentally aligning with the Unix timestamp rollover, marking this a significant milestone in my lifelong observations.

Examining NVIDIA's progression offers a clear illustration of this rapid advancement:

\- GeForce GTX 1080 (2016): 11.3 TFLOPS

\- GeForce RTX 2080 (2018): 14.2 TFLOPS

\- GeForce RTX 3090 (2020): 35.6 TFLOPS

\- GeForce RTX 4090 (2022): 82.6 TFLOPS

Notably, the RTX 4090 represents a significant leap forward, albeit at the cost of increased power consumption. Nevertheless, this trend reaffirms the continuation of Moore's Law, with computational power roughly doubling every two years.

In today's market, strategically increasing your investment can effectively "purchase" an advancement of two years into the future of computing power. For instance, Facebook's acquisition of a cluster of 2048 GPUs represents an advancement of approximately 11 Moore's Law cycles, or about 16 years ahead of the current standard, assuming you can invest in an eight-GPU setup.

George Hotz defines a benchmark for what we'll call a "person of compute" at 20 PFLOPS, equivalent to using 64 A100 GPUs or filling a single 42U server rack with A100 units. We're navigating through a phase where one such server rack, symbolizing a "person" in computational power, demands around 30kW of energy to deliver those 20 PFLOPS.  
  
The actual cost of the entry barrier is how much energy an organization can consume to transform it into intellect. The dominance of a few cloud companies and chip manufacturers in providing the necessary infrastructure for AI development has created a skewed market. The high cost of accessing this compute power ($250k for a person of compute) places smaller entities at a significant disadvantage. AI development is being centralized, and that opens Pandora’s boxes (access, influenced judgment and output, backdoors, telemetry).

Looking at machine learning models in isolation doesn't reveal their actual value; these models depend heavily on computational power, which relies on silicon chip production. The genuine worth emerges from generating tangible resources that can be traded or utilized, a value that can be significantly enhanced by leveraging software or scientific advancements. Creating and maintaining silicon chips necessitate skilled personnel to manage the machinery and the software. However, only a select group of companies globally possess the financial resources and technical know-how required to manufacture these chips. Only a few are in a position to purchase. It's critical to secure access to computational resources at reasonable market rates if autonomy is a priority for our software brains.

Cloud service providers have capitalized on the cloud revolution of the 2010s by offering storage, networking, and generic compute to SMBs and startups. They now leverage the wealth amassed to gain specialized computational capabilities. Balancing the scales with these giants involves shifting away from their dominance in general computing tasks by developing software that minimizes reliance on high-level computational abstractions.

Major computing firms seem reticent to assist smaller-scale projects. This can be seen in actions such as Nvidia's or AMD’s hesitance to provide comprehensive documentation for their GPUs.
