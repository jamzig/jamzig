#!/bin/bash

# Needs modified version of polkatool to be albe to use jam-assemble

for asm_file in *.asm; do
    output_file="${asm_file%.asm}.jampvm"
    polkatool jam-assemble --output "$output_file" "$asm_file"
done
