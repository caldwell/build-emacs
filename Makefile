EXE:=launch
SOURCES:=launch.rs
ARCHES:=aarch64 x86_64

ARCH_DIRS=$(patsubst %,target/%-apple-darwin/release/,$(ARCHES))
ARCH_EXES=$(addsuffix $(EXE),$(ARCH_DIRS))

all: $(EXE)

$(EXE): $(ARCH_EXES)
	lipo -create -output $@ $^

target/%-apple-darwin/release/$(EXE): $(SOURCES)
	rustup run nightly-$*-apple-darwin cargo build --release --target=$*-apple-darwin
