# Pipette
Pipette is an ASIC hardware accelerator designed to optimize Power, Performance, and Area (PPA) for General Matrix Multiply (GEMM) operations. Developed as an EE 478 Capstone Project at the University of Washington, this project evaluates the architectural trade-offs between a conventional Weight-Stationary (WS) Systolic Array and a novel, optimized Twisted Torus Systolic Array.

Team Members: Vance Borus, Sachal Shaikh, Byeongguk Lee, Chenyi Wang, Neal Causey, and Sean Bubernak.

Advisors: Professor Ang Li (University of Washington) and Jiayi Wang (Ph.D. student).

Project Status: GDSII submitted to TSMC (DRC/LVS clean, timing closed). Awaiting fabrication for silicon bring-up and physical validation.

# Repository Description
```bash
├── docs/          # Architecture specifications, pinout diagrams, and register maps
├── v/             # Synthesizable RTL (Verilog) and comprehensive testbenches
├── scripts/       # Automation, verification, and data-processing scripts (Python, Tcl, Perl)
└── synthesis/     # Physical design and synthesis scripts for the TSMC 180nm Hammer flow
```
[!IMPORTANT]
NDA Compliance Notice: All TSMC 180nm standard cell libraries, IO pad cells, and foundry-specific Hammer configurations have been omitted to strictly adhere to non-disclosure agreements.

# Problem Statement
<img width="1920" height="1163" alt="image" src="https://github.com/user-attachments/assets/9374a5dd-eb9a-4fec-9423-0329f9923dbc" />
The Cost of Input Skewing in Conventional WS Arrays are the main motivator for this novel architecture. In a standard Weight-Stationary Tensor Processing Unit (TPU), executing a matrix multiplication ($A \times B = C$) requires the inputs of matrix $A$ to be fed in a staggered, skewed fashion. This ensures that the moving activations intersect with the correct stationary weights ($B_{ij}$) and that partial sums accumulate synchronously across the Processing Elements (PEs).This conventional approach introduces two major hardware inefficiencies:
<img width="1728" height="822" alt="image" src="https://github.com/user-attachments/assets/2a048ae4-f2a7-4bd9-913e-47492e2e8ac8" />
1. Area Overhead: Substantial Silicon area is consumed by external shift-register arrays (represented by the red triangular buffers below) required to stagger input data.
2. Latency & Throughput Degradation: Input skewing increases execution latency. For a $4 \times 4$ array, computation stretches to 7 cycles instead of a theoretical 4-cycle minimum. While continuous streaming can hide this latency for static weights, frequently changing weights break the pipeline. The hardware must stall to load new weights, severely penalizing throughput in workloads with dynamic weight updates.

## Prior Art: The Twisted Torus Architecture
Prior academic work ([IEEE Exploration, 2025](https://ieeexplore.ieee.org/document/11098764)) demonstrated that spatial skewing can be eliminated by wrapping peripheral processing elements back into a standard $N \times N$ grid structure.By introducing secondary wraparound links from the bottom row back to the top ($B_{4j}$ to $B_{1j}$), the architecture forms a Twisted Torus. This allows perfectly aligned rows of matrix $A$ to be injected into the array simultaneously. However, this architectural fix introduces a massive physical implementation bottleneck: long, non-local interconnects that degrade timing closure, increase dynamic power consumption, and complicate routing.

# Our Solution: Shuffled 1-Hop Twisted Torus
Proposed by Prof. Ang Li, Pipette addresses the long-interconnect bottleneck by applying a deterministic shuffling algorithm to the Twisted Torus topology. By altering the routing matrix, we ensure that every physical interconnect is constrained to a maximum of 1-hop. To support this localized routing, the datapath is re-architected so that activations, weights, and partial sums move diagonally through the array.

# Diagrams
## Weight Loading Phase

<table>
  <tr>
    <td><strong>Cycle 1</strong><br><img src="https://github.com/user-attachments/assets/aed7af6b-772a-4870-996e-4beac89a0782" width="200"/></td>
    <td><strong>Cycle 2</strong><br><img src="https://github.com/user-attachments/assets/6f02ecb6-5f73-41a5-b2f0-b5923f15ba2c" width="200"/></td>
    <td><strong>Cycle 3</strong><br><img src="https://github.com/user-attachments/assets/3393c972-010c-4a68-8688-c8afa0982b28" width="200"/></td>
    <td><strong>Cycle 4</strong><br><img src="https://github.com/user-attachments/assets/db739d6e-59ea-4011-aa43-90d0048e84a3" width="200"/></td>
  </tr>
</table>

## Compute Phase

<table>
  <tr>
    <td><strong>Cycle 5</strong><br><img src="https://github.com/user-attachments/assets/80389978-df2d-4328-a97f-5ff6de7ee1fe" width="200"/></td>
    <td><strong>Cycle 6</strong><br><img src="https://github.com/user-attachments/assets/7a52fb36-a4b2-415d-a422-ea5ad6502692" width="200"/></td>
    <td><strong>Cycle 7</strong><br><img src="https://github.com/user-attachments/assets/59a82273-c48d-408f-9648-34a37814c9c6" width="200"/></td>
    <td><strong>Cycle 8</strong><br><img src="https://github.com/user-attachments/assets/d7ae1815-c08c-44d4-a994-78890d31c378" width="200"/></td>
  </tr>
</table>
