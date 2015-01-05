PREFIX=/usr
INSTALL=install

gen:
	echo 'generating dissectors/atoms'
	cd interceptor && (mkdir gen; mkdir gen/RequestDissector; mkdir gen/ReplyDissector; perl _GenerateDissectors.pl && perl _PredefineAtoms.pl)

install: gen
	echo 'install!'
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/bin
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/lib/x11vis
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/lib/x11vis/gui
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/lib/x11vis/gui/gen
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/lib/x11vis/gui/templates
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/lib/x11vis/interceptor
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/lib/x11vis/interceptor/lib
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/lib/x11vis/interceptor/lib/Dissector
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/lib/x11vis/interceptor/gen
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/lib/x11vis/interceptor/gen/RequestDissector
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/lib/x11vis/interceptor/gen/ReplyDissector
	$(INSTALL) -m 0755 bin/x11vis $(DESTDIR)$(PREFIX)/bin/x11vis
	$(INSTALL) -m 0755 gui/*.js $(DESTDIR)$(PREFIX)/lib/x11vis/gui/
	$(INSTALL) -m 0755 gui/*.gif $(DESTDIR)$(PREFIX)/lib/x11vis/gui/
	$(INSTALL) -m 0755 gui/*.html $(DESTDIR)$(PREFIX)/lib/x11vis/gui/
	$(INSTALL) -m 0755 gui/*.css $(DESTDIR)$(PREFIX)/lib/x11vis/gui/
	$(INSTALL) -m 0755 gui/templates/*.html $(DESTDIR)$(PREFIX)/lib/x11vis/gui/templates
	$(INSTALL) -m 0755 interceptor/interceptor.pl $(DESTDIR)$(PREFIX)/lib/x11vis/interceptor/
	$(INSTALL) -m 0644 interceptor/lib/*.pm $(DESTDIR)$(PREFIX)/lib/x11vis/interceptor/lib/
	$(INSTALL) -m 0644 interceptor/lib/Dissector/*.pm $(DESTDIR)$(PREFIX)/lib/x11vis/interceptor/lib/Dissector/
	$(INSTALL) -m 0644 interceptor/gen/*.pm $(DESTDIR)$(PREFIX)/lib/x11vis/interceptor/gen/
	$(INSTALL) -m 0644 interceptor/gen/RequestDissector/*.pm $(DESTDIR)$(PREFIX)/lib/x11vis/interceptor/gen/RequestDissector/
	$(INSTALL) -m 0644 interceptor/gen/ReplyDissector/*.pm $(DESTDIR)$(PREFIX)/lib/x11vis/interceptor/gen/ReplyDissector/
	$(INSTALL) -m 0644 interceptor/gen/*.json $(DESTDIR)$(PREFIX)/lib/x11vis/gui/gen/

all: gen

.PHONY: clean
clean:
	-rm -r interceptor/gen
