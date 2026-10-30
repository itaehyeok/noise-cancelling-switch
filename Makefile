.PHONY: all run install clean

all:
	@./build.sh build

run:
	@./build.sh run

install:
	@./build.sh install

clean:
	@./build.sh clean
