#!/usr/bin/python
import sys
import os

# extract the bytes in format
# 12M 13K 4G


def extract_bytes(line):
    line = line.strip().lower().replace('\t', ' ')
    tmp = line.partition(' ');
    try:
        num_str = tmp[0].strip()
        num_str = num_str.replace(',', '.')
        if num_str.endswith('g'):
            num = float(num_str[0:len(num_str)-1])*1024*1024*1024
        elif num_str.endswith('m'):
            num = float(num_str[0:len(num_str)-1])*1024*1024
        elif num_str.endswith('k'):
            num = float(num_str[0:len(num_str)-1])*1024
        else:
            num = float(num_str)
    except:
        num = 0

    return num


def main():
    lines = []
    for line in sys.stdin:
        lines.append(line)

    key_lines = []
    for i in lines:
        key_lines.append([extract_bytes(i),i])

    key_lines = sorted(key_lines, key=lambda v: v[0])

    for i in key_lines:
        print i[1].strip()


if __name__ == '__main__':
    main()

