#!/bin/bash
allThreads=(1 "2" 4 8 16 32 64 128);

for t in ${allThreads[@]}; do
  echo $t
done