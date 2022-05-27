.PHONY: all test clean

TOP=.

all: navigation.so

CFLAGS = $(CFLAG)
CFLAGS += -g3 -O2 -rdynamic -Wall -fPIC -shared

navigation.so: luabinding.c jps.c fibheap.c
	gcc $(CFLAGS) -o $@ $^

clean:
	rm navigation.so

test:
	lua test/test.lua
