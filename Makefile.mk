.PHONY: all test clean debug navigation
	all: grid

CFLAGS= -g3 -std=c99 -O0 -rdynamic -Wall -fPIC -shared

all: navigation test

navigation: navigation.so
navigation.so: luabinding.c jps.c node_freelist.c intlist.c
	    gcc $(CFLAGS) -o $@ $^

test:
	lua test/test.lua

clean:
	rm -f *.so

debug: CFLAGS += -DDEBUG
debug: navigation test
