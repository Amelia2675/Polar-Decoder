# Polar Decoder
Polar codes are error-correcting codes. It aims to transmit messages at the highest possible rate through the class of channels. However, not every channel is used because channel coding needs to add redundancy. The frozen channel index is known to both transmitter and decoder. The known frozen channel helps enhance the rate of transmission.

## Block Diagram
<img width="488" alt="image" src="https://user-images.githubusercontent.com/109503040/225305013-5f9629be-4565-4796-b9a6-b0406addbe9e.png">

## Architecture
### Read data
LLR memory contains 1~44 polar encoded packets, each with different N and K. Additionally, contents in LLR memory will be ready before the signal 'module_en' rises.
<img width="477" alt="image" src="https://user-images.githubusercontent.com/109503040/225306976-eabff0e3-027d-4e92-87b5-a442bf71ae8f.png">

1 packet involves 32 words. There are 3 specifications for N - 128, 256, and 512. 
We utilized the number of N to define the amount of clock cylces that the system takes to read data from LLR memory.

### Output format & Frozen bit
Hard bit, the output of decoder, is 0 if the bit is defined as a frozen bit. 
Under the circumstances hard bit is not a frozen bit, it will be 1 when x is smaller than zero; and it will be 0 when x is larger than zero.

### Decode Strategy
#### SC decoder
<img width="722" alt="image" src="https://user-images.githubusercontent.com/109503040/225307207-623e2819-ac3a-4e93-860a-fb6eef4f7c52.png">
The process of decoding is separated into 'f function' and 'g funciton.'

## Optimization
In the beginning, we unfolded all the decoder and diretly computated. In order to optimize the performace, we decreased the number of 'f' nodes and 'g' nodes. Furthermore, area, power, and amount of clock cycles are also taken into account. The ways of optimization we took are as following: 
### Register Sharing
Merge 2 functions into 1 computation cell. This method declined not only the area but also the power of the design.
### Dwindle Cycle Time
At first, we read all the data in one sitting. Afterwards, we pruned the design to implement decoding as soon as it gains 2 words from the memory.
### Zero Node Cancellation
Predict the position of frozen bits when decoding. Then skip the redundant nodes to compute non-frozen bits.
### Compilation Method
```sh
compile_ultra
clock_gating
```
Using some demands in synthesis to shrink area and power.
### APR
1. Reduce the amount of stripes.
2. Increase the amount of fanout.
