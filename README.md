# write-thru-hash
Racket (mutable) [hash-table impersonators](https://docs.racket-lang.org/reference/chaperones.html#%28def._%28%28quote._~23~25kernel%29._impersonate-hash%29%29), backed by persistent storage.

The hash-table will then behave like a write-thru cache, any updates to the hash are persisted to the db and any lookups come directly from the hash-table itself.

* [Installation](#installation)
* [Requirements](#requirements)
* [Usage](#usage)
* [Motivating example](#motivating-example)

### Installation

To install:
```
raco pkg install https://github.com/anentropic/rkt-write-thru-hash.git
```

...or to install without having `sql` dependency bring in the whole world:
```
raco pkg install --binary --no-docs sql
raco pkg install https://github.com/anentropic/rkt-write-thru-hash.git
```
(I guess this will not be necessary if I get around to uploading `write-thru-hash` to the package manager)

### Requirements

`make-db-hash` uses the `INSERT ... ON CONFLICT UPDATE` SQL statement to do an 'upsert' operation.

This means the following dbs are supported:
* SQLite > [3.24](https://phoronix.com/scan.php?page=news_item&px=SQLite-3.24-Released-UPSERT) (...a lot of systems have an older version pre-installed)
* Postgres > 9.5
* any other db which supports this upsert syntax, via an ODBC connection

MySQL would be possible but it uses a different upsert syntax, so is not supported for now.

All are using [Racket db](https://docs.racket-lang.org/db/).

### Usage

Currently this lib provides one function: `make-db-hash`.

Its signature looks like:
```racket
(define (make-db-hash db-conn #:table-name   [table-name DEFAULT-TABLE-NAME]
                              #:src-hash     [src-hash #f]
                              #:serializer   [serializer DEFAULT-SERIALIZER]
                              #:deserializer [deserializer DEFAULT-DESERIALIZER])
    ...)

[make-db-hash (->* (connection?)
                   (#:table-name string?
                    #:src-hash (or/c false? serializable-hash/c)
                    #:serializer (-> serializable? string?)
                    #:deserializer (-> string? serializable?))
                   (and/c serializable-hash/c (not/c immutable?)))]
```

The one required arg, `db-conn`, is a database connection from the Racket `db` lib.

The first time you connect to a db, the storage table `<table-name>` will be created.

If the table already exists then any existing data in it will be pre-loaded into the resulting hash.

Instead, if an existing hash-table is supplied as `src-hash`, the db storage will be cleared and re-initialised with data from `src-hash`.

Keys and values are both serialized before writing to the db and deserialized when read initially.

So a basic usage example would look like:

```racket
(require db write-thru-hash)

(define db-conn (sqlite3-connect #:database "./db.sqlite"
                                 #:mode 'create))

(define myhash (make-db-hash db-conn))

(hash-set! myhash 'a 1)
(hash-set! myhash 'b 2)
(hash-set! myhash 'c 3)
(hash-remove! myhash 'c)
```

If you now close your `racket` session and open a new one:
```racket
(require db write-thru-hash)

(define db-conn (sqlite3-connect #:database "./db.sqlite"
                                 #:mode 'create))

(define myhash (make-db-hash db-conn))

(writeln myhash)
; #hash((a . 1) (b . 2))
```
...we can see the data was persisted to the db and reloaded into `myhash` when connecting it to the same db+table.

NOTE: Currently this is a one-way sync (hash->db) only. This means that if you instantiate multiple hash-tables from the same db+table, changes you make in any hash will be persisted to the db but won't be reflected in the contents of the other hashes for lookups.

I have no immediate plans to fix this, it's recommended just to have a 1-1 relation between hash-table and db+table.

NOTE: The resulting hash is an `any/any` hash. If you initialised it with a `src-hash` built using `make-custom-hash` and having a specific type contract then this contract won't be preserved.

### Motivating example

I was looking into the [Racket datalog](https://docs.racket-lang.org/datalog/) library. It has some basic support for dumping and loading the 'theory' (datalog db) from a file. For various pointless reasons I was daydreaming about a scenario where I would want "incremental persistence" for the datalog theory data, i.e. as you assert and retract facts during operation each change would be persisted. I also imagined it may get slow to dump the whole structure each time (in this daydream, where I had a large db and frequent updates...).

Peeking under the covers I found that the datalog 'theory' is just a mutable hash-table.  So what I needed, in the daydream, was an object that could pass as a mutable hash-table but would behave as a write-through cache to some storage. Hence this `write-thru-hash`.

And it works, here is the typical family tree example, but with incremental persistence:

```racket
(require datalog db write-thru-hash)

(define db-conn
    (sqlite3-connect #:database "./datalog.sqlite"
                     #:mode 'create))

(define family (make-db-hash db-conn))

(datalog family
    (! (male abe))
    (! (male homer))
    (! (male bart))
    (! (female marge))
    (! (female lisa))
    (! (female maggie))
    (! (parent abe homer))
    (! (parent homer bart))
    (! (parent homer maggie))
    (! (parent homer lisa))
    (! (parent marge bart))
    (! (parent marge lisa))
    (! (parent marge maggie))
    (! (:- (father X Y) (parent X Y) (male X)))
    (! (:- (mother X Y) (parent X Y) (female X)))
    (! (:- (grandparent X Z) (parent Y Z) (parent X Y)))
    (! (:- (grandfather X Y) (grandparent X Y) (male X)))
    (! (:- (grandmother X Y) (grandparent X Y) (female X)))
    (! (:- (child X Y) (parent Y X)))
    (! (:- (son X Y) (child X Y) (male X)))
    (! (:- (daughter X Y) (child X Y) (female X)))
    (! (:- (sibling X Y) (parent Z X) (parent Z Y) (!= X Y)))
    (! (:- (brother X Y) (sibling X Y) (male X)))
    (! (:- (sister X Y) (sibling X Y) (female X))))

; reload from db into a new identifier...
(define reloaded (make-db-hash db-conn))

; we have a usable datalog theory with the persisted data...
(check-equal?
    (datalog reloaded (? (sister X bart)))
    '(#hasheq((X . lisa)) #hasheq((X . maggie))))
(check-equal?
    (datalog reloaded (? (father X lisa)))
    '(#hasheq((X . homer))))
(check-equal?
    (datalog reloaded (? (grandfather X maggie)))
    '(#hasheq((X . abe))))
```
