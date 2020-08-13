FROM racket/racket:7.7-full

# use newer sqlite3 already present in the image
# (instead of old 3.22 from the racket lib dir)
COPY docker/config.rktd /usr/etc/racket/config.rktd

# pre-install some deps...
RUN raco pkg install --no-docs --auto sql fixture disposable

RUN mkdir -p write-thru-hash
COPY *.rkt write-thru-hash/

RUN raco pkg install --no-docs --auto write-thru-hash/

CMD ["racket"]
