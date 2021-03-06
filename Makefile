# OASIS_START
# DO NOT EDIT (digest: bc1e05bfc8b39b664f29dae8dbd3ebbb)

SETUP = ocaml setup.ml

build: setup.data
	$(SETUP) -build $(BUILDFLAGS)

doc: setup.data build
	$(SETUP) -doc $(DOCFLAGS)

test: setup.data build
	$(SETUP) -test $(TESTFLAGS)

all: 
	$(SETUP) -all $(ALLFLAGS)

install: setup.data
	$(SETUP) -install $(INSTALLFLAGS)

uninstall: setup.data
	$(SETUP) -uninstall $(UNINSTALLFLAGS)

reinstall: setup.data
	$(SETUP) -reinstall $(REINSTALLFLAGS)

clean: 
	$(SETUP) -clean $(CLEANFLAGS)

distclean: 
	$(SETUP) -distclean $(DISTCLEANFLAGS)

setup.data:
	$(SETUP) -configure $(CONFIGUREFLAGS)

.PHONY: build doc test all install uninstall reinstall clean distclean configure

# OASIS_STOP

LOG_DIR = ./local/var/log
LIB_DIR = ./local/var/lib

run: install-data $(LOG_DIR) $(LIB_DIR)
	CAML_LD_LIBRARY_PATH="${CAML_LD_LIBRARY_PATH}:_build/src/core" ocsigenserver -c local/etc/ocsigen/ocsimore.conf -v

restart: install-data
	echo restart > /tmp/cpipe

STATIC_DIR = ./local/var/www/static/

.PHONY:
install-data: ${STATIC_DIR}
	cp ./_build/src/site/client/ocsimore.js $<

${STATIC_DIR}:
	mkdir -p $@

${LOG_DIR}:
	mkdir -p $@

${LIB_DIR}:
	mkdir -p $@
