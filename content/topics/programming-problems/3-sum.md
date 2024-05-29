---  
share: true  
title: 3 Sum  
aliases:  
  - 3 Sum  
---  
[Home](../../index.md) > [Topics](../index.md) > [Programming Problems](./index.md)  
# 3 Sum  
## Problem Statement  
Given an array of integers, return 3 integers that sum to zero if possible.  
  
## Clarifications  
1. If multiple solutions exist, return any of them  
2. Each element can only be used once  
  
## Examples  
0 0 0 -> 0 0 0  
0 0 -> None  
1 0 1 -> None  
-1 0 1 -> -1 0 1  
-1 5 1 6 0 -> -1 1 0  
  
## Potential Solutions  
### Brute Force  
#### Algorithm  
1. Generate all possible triples  
2. Compute the sum of each  
3. When finding a triple that sums to zero, return it  
4. If none is found, indicate as much  
#### Time Complexity  
To generate all triples, use 3 nested for-loops  
O(N^3)  
#### Space Complexity  
There's no need to store the triples, as we'll return as soon as we find one.  
O(1)  
  
### 1 + Naive 2 Sum  
#### Algorithm  
1. For each integer i, examine the remaining integers looking for 2 that sum to -i  
2. As each integer is examined, it never needs to be examined again, thus each iteration gets smaller  
3.   
  
#### Time Complexity  
O(N) + O(N - 1) + O(N - 2) + ... + O(1)  
= O(N + N - 1 + N - 2 + ... + 1)  
* Sum of integers from 1 to n: S(N) = N * (N + 1) / 2 = (N^2 + N)/2  
= O((N^2 + N)/2)  
= O(N^2 + N)  
= O(N^2)  
-1 5 1 6 0 -> -1 1 0  
  
A = -1  
B = 5  
5 + 1 = 6 != 1  
5 + 6 = 11 != 1  
5 + 0 = 5 != 1  
=> No solution for -1,5 exists  
B = 1  
1 + 6 = 7 != 1  
1 + 0 = 1 == 1  
=> Solution found!  
  
### O(N^2 * log(N)) - Presort; 2-sum binary search  
1. O(N * log(N)) - Sort the input array  
2. O(N^2 * log(N)) - For each element A, search for 2-sum = -A; -A = (B + C)  
  1.  O(N * log(N)) - 2-sum: for each element B, binary-search for C = -A - B  
      1. O(log(N)) - binary-search  
// log(N) + log(N - 1) + ... + log(1)  
Fact: log(M) + log(N) = log(M * N)  
// Sum i=1 -> N { log(i) } = log(N!)  
Stirling's approximation: log(N!) = N * log(N) - N  
  
#### Example 1  
```  
I = -1 5 1 6 0  
S = -1 0 1 5 6  
A = -1  
B = 0  
0 + 1 = 1 == 1  
```  
=> Solution found! (-1,0,1)  
  
#### Example 2  
```  
I = -11 5 1 6 0  
S = -11 0 1 5 6  
A = -11  
B = 0  
0 + 1 = 1 != 11  
0 + 5 = 5 != 11  
0 + 6 = 6 != 11  
```  
=> No solution exists for -11,0  
```  
B = 1  
1 + 5 = 6 != 11  
1 + 6 = 7 != 11  
```  
=> No solution exists for -11,1  
```  
B = 5  
5 + 6 = 11 == 11  
```  
=> Solution found! (-11,5,6)  
  
#### Example 3  
```  
I = -11 5 -12 6 -13  
S = -13 -12 -11 5 6  
A = -13  
B = -12  
-12 + -11 = -23 != 13  
-12 + 5 = -7 != 13  
-12 + 6 = -1 != 13  
```  
=> No solution exists for -13,-12  
```  
B = -11  
-11 + 5 = -6 != 13  
-11 + 6 = -5 !+ 13  
```  
=> No solution exists for -13,-11  
```  
B = 5  
5 + 6 = 11 != 13  
```  
=> No solution exists for -13,5  
=> No solution exists for -13  
```  
A = -12  
B = -11  
-11 + 5 = -6 != 12  
-11 + 6 = -5 != 12  
```  
=> No solution exists for -12,-11  
```  
B = 5  
5 + 6 = 11 != 12  
```  
=> No solution exists for -12,5  
=> No solution exists for -12  
```  
A = -11  
B = 5  
5 + 6 = 11 == 11  
```  
=> Solution found! (-11,5,6)  
  
### 1 + 2-pointer 2-sum  
#### Algorithm  
1. O(N * log(N)) - Sort the input array  
2. O(N^2) - For each element A of the input array, find the 2-sum of the remaining array equal to -A  
  1. O(N) - 2-sum: Using 2 pointers starting at beginning and end, iterate forward and backward as the sum toggles greater and less than the target  
