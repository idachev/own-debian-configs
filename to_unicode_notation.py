#!/usr/bin/env python

import sys


def print_to_unicode_notation(str):
   out = ""
   for c in str:
      out += ("<U%04X>" % ord(c))
   print(out)


def main():
   if len(sys.argv) <= 1:
      print("Expected string argument.")
      sys.exit(1)

   arg = sys.argv[1]
   print_to_unicode_notation(arg)


if __name__ == '__main__':
   main()
