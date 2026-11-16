PREFIX  ?= /usr
BINDIR  ?= $(PREFIX)/bin
LIBDIR  ?= $(PREFIX)/lib/amu
MANDIR  ?= $(PREFIX)/share/man/man8
DOCDIR  ?= $(PREFIX)/share/doc/amutils

SCRIPTS = amu amu-src amu-bin amu-resolv amu-trigger reposync updateconf genfstab qlchroot

.PHONY: all install uninstall

all:
	@echo "Run 'make install' to install amutils."

install:
	mkdir -p $(DESTDIR)$(BINDIR) $(DESTDIR)$(LIBDIR) $(DESTDIR)$(MANDIR) $(DESTDIR)$(DOCDIR)
	install -m755 $(SCRIPTS:%=bin/%) $(DESTDIR)$(BINDIR)/
	install -m644 lib/libam.sh $(DESTDIR)$(LIBDIR)/libam.sh
	install -m644 man/*.8 $(DESTDIR)$(MANDIR)/
	install -m644 doc/amu.conf.example doc/recipe.md doc/buildopts.md $(DESTDIR)$(DOCDIR)/

uninstall:
	for f in $(SCRIPTS); do rm -f $(DESTDIR)$(BINDIR)/$$f; done
	rm -f $(DESTDIR)$(LIBDIR)/libam.sh
	for f in man/*.8; do rm -f $(DESTDIR)$(MANDIR)/$$(basename $$f); done
	rm -f $(DESTDIR)$(DOCDIR)/amu.conf.example $(DESTDIR)$(DOCDIR)/recipe.md $(DESTDIR)$(DOCDIR)/buildopts.md
