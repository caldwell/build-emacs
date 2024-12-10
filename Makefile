EXE:=launch
SOURCES:=launch.rs
ARCHES:=aarch64 x86_64

ARCH_DIRS=$(patsubst %,target/%-apple-darwin/release/,$(ARCHES))
ARCH_EXES=$(addsuffix $(EXE),$(ARCH_DIRS))

all: $(EXE)

$(EXE): $(ARCH_EXES)
	lipo -create -output $@ $^

target/x86_64-apple-darwin/release/%: export MACOSX_DEPLOYMENT_TARGET=10.11
target/%-apple-darwin/release/$(EXE): $(SOURCES)
	cargo build --release --target=$*-apple-darwin
