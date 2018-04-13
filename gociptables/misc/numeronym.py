#!/usr/bin/python

import sys
import re

for line in sys.stdin:
    list = re.findall(r"[a-zA-Z]+|[^a-zA-Z]+", line)
    list2 = []
    for item in list:
        if re.match(r"[a-zA-Z]", item[0]) and len(item) > 3:
            item = item[0] + "%d" % (len(item) - 2) + item[-1]
        list2.append(item)
    print ''.join(list2),
