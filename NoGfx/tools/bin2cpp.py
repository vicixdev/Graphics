#!/usr/bin/env python3

import argparse
import os
import logging as log
import re

def to_c_identifier(s: str) -> str:
    s = re.sub(r'[^a-zA-Z0-9_]+', '_', s).strip('_')

    if not s:
        return "_"

    if s[0].isdigit():
        s = '_' + s

    return s

argument_parser = argparse.ArgumentParser(
    prog='bin2cpp',
    description='Converts any file to a cpp file that you can include in your C/C++ project.'
)
argument_parser.add_argument('input')
argument_parser.add_argument('-o', '--output', default=None)
argument_parser.add_argument('-H', '--header', default=None)
argument_parser.add_argument('-v', '--variable', default=None)

arguments = argument_parser.parse_args()

try:
    with open(arguments.input, 'rb') as f:
        input = f.read()
except:
    log.error(f'Could not open input file `{arguments.input}`')
    exit(-1)

variable_name = arguments.variable if arguments.variable is not None else '_' + to_c_identifier(arguments.input)
output = f'const unsigned char {variable_name}[{len(input)}] = {{ '

is_first = True
for b in input:
    if not is_first:
        output += ', '
    output += f'0x{b:02x}'
    is_first = False
output += ' };\n'

output_file = arguments.output if arguments.output is not None else arguments.input + '.inc'
try:
    with open(output_file, 'w') as f:
        f.write(output)
except:
    log.error(f'Could not open output file `{output_file}`')
    exit(-1)

if arguments.header is not None:
    output = f'#ifndef {variable_name.capitalize()}_H\n#define {variable_name.capitalize()}_H\n\nextern const unsigned char {variable_name}[{len(input)}];\n\n#endif\n'
    output_file = arguments.output if arguments.output is not None else arguments.input + '.inc'
    try:
        with open(arguments.header, 'w') as f:
            f.write(output)
    except:
        log.error(f'Could not open output file `{output_file}`')
        exit(-1)

