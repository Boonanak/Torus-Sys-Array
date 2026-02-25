# Torus-Sys-Array
EE 478 Capstone Project. Testing PPA differences between a conventional weight-stationary systolic array and a new torus architecture systolic array

# Problem we intend to address
<img width="1920" height="1163" alt="image" src="https://github.com/user-attachments/assets/07a91294-237e-40b5-9c24-dea08b597701" />
As this wikipedia image from [https://en.wikipedia.org/wiki/Systolic_array#/media/File:Weights_Stationary_Systolic_Array_Example.png](URL) shows, 
When we want to do a matrix multiply operation A x B = C with a weight stationary TPU, each individual PE at location (i, j) is loaded with weights of matrix B_ij, and the weights of matrix A is fed in this skewed manner to ensure partial sums (accumulated values) arrive on time and at correct places.
<img width="1728" height="822" alt="image" src="https://github.com/user-attachments/assets/df279c21-77e1-44ff-a03b-01678f754cf6" />
this creates two problems. first is that area efficiency of systolic array is reduced from the shift registers in red triangular area to correctly support skew. second is that now compute takes 7 cycles, instead of four if all the rows are aligned. this can be problematic in cases where it is compute bound and matrix weights of B is consistently changing, because the total matrix multiplication operation takes (cycles to load matrix B + cycles to shift A through PE's) and this impacts not only latency but also throughput. note that if matrix B rarely changes and next data is always ready, we can coalesce next and previous weights of matrix A and we would have same throughput as if we had all data aligned, but if B frequently changes we cannot do that because we must wait for B to correctly be loaded into the systolic array.

## Reference Solution
simply rearranging the diagram a bit does not solve the problem as there are still shift registers and skew problem, but reveals us an idea that leads to this publication: https://ieeexplore.ieee.org/document/11098764
<img width="1574" height="549" alt="image" src="https://github.com/user-attachments/assets/e1aeaab8-4eea-4823-9365-575d819bb32a" />
The core idea is that we can wrap around the PE's that extend out of regular 4x4 grid structure (B24, B33, B34, B42, B43, B44) and bring it back into the 4x4 grid.
<img width="1543" height="719" alt="image" src="https://github.com/user-attachments/assets/7019c8ea-4b85-43e6-8768-fb9d9dcd11a3" />
There are additional wraparound link from B_4j to B_1j to accomodate for the changes, which leads us to a twisted torus shaped systolic array.
these wraparound links are long interconnects, which poses significant timing, power, and routing issues.

# Solution (work in progress)
We intend on minimizing the interconnect length by applying additional shuffling to the twisted torus based TPU.
