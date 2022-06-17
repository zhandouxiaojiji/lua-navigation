.PHONY: all test clean

TOP=.

all: navigation.so

CFLAGS = $(CFLAG)
CFLAGS += -g3 -O2 -rdynamic -Wall -fPIC -shared

navigation.so: luabinding.c map.c jps.c fibheap.c smooth.c
	gcc $(CFLAGS) -o $@ $^

clean:
	rm navigation.so

test:
	lua test/test.lua
