#!/bin/bash
awk -F'/' '{                                                                                                           
  f = $NF
  a[f] = f in a? a[f] RS $0 : $0
  b[f]++ } 
  END{for(x in b)
        if(b[x]>1)
          printf "Duplicate Filename: %s\n%s\n",x,a[x] }' <(find . -type f -iname "${1}")
