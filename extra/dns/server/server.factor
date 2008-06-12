
USING: kernel combinators sequences sets math
       io.sockets unicode.case accessors
       combinators.cleave combinators.lib
       newfx
       dns dns.util dns.misc ;

IN: dns.server

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

: records ( -- vector ) V{ } ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

: {name-type-class} ( obj -- array )
  { [ name>> >lower ] [ type>> ] [ class>> ] } <arr> ;

: rr=query? ( obj obj -- ? ) [ {name-type-class} ] bi@ = ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

: matching-rrs  ( query -- rrs ) records [ rr=query? ] with filter ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! zones
! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

: zones    ( -- names ) records [ type>> NS  = ] filter [ name>> ] map prune ;
: my-zones ( -- names ) records [ type>> SOA = ] filter [ name>> ] map ;

: delegated-zones ( -- names ) zones my-zones diff ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! name->zone
! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

: name->zone ( name -- zone/f )
  zones sort-largest-first [ name-in-domain? ] with find nip ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! fill-authority
! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

: fill-authority ( message -- message )
  [ ]
  [ message-query name>> name->zone NS IN query boa matching-rrs ]
  [ answer-section>> ]
  tri
  diff >>authority-section ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! fill-additional
! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

: rr->rdata-names ( rr -- names/f )
    {
      { [ dup type>> NS = ] [ rdata>>            {1} ] }
      { [ dup type>> MX = ] [ rdata>> exchange>> {1} ] }
      { [ t ]               [ drop f ] }
    }
  cond ;

: fill-additional ( message -- message )
  dup
  [ answer-section>> ] [ authority-section>> ] bi append
  [ rr->rdata-names ] map concat
  [ A IN query boa matching-rrs ] map concat prune
  over answer-section>> diff
  >>additional-section ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! query->rrs
! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

DEFER: query->rrs

: matching-rrs? ( query -- rrs/f ) matching-rrs [ empty? ] [ drop f ] [ ] 1if ;

: matching-cname? ( query -- rrs/f )
  [ ] [ clone CNAME >>type matching-rrs ] bi ! query rrs
  [ empty? not ]
    [ 1st swap clone over rdata>> >>name query->rrs prefix-on ]
    [ 2drop f ]
  1if ;

: query->rrs ( query -- rrs/f ) { [ matching-rrs? ] [ matching-cname? ] } 1|| ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! have-answers
! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

! : have-answers ( message -- message/f )
!   dup message-query query->rrs        ! message rrs/f
!   [ empty? ] [ 2drop f ] [ >>answer-section ] 1if ;

: have-answers ( message -- message/f )
  dup message-query query->rrs
  [ empty? ]
    [ 2drop f ]
    [ >>answer-section fill-authority fill-additional ]
  1if ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! have-delegates?
! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

: cdr-name ( name -- name ) dup CHAR: . index 1+ tail ;

: is-soa? ( name -- ? ) SOA IN query boa matching-rrs empty? not ;

: have-ns? ( name -- rrs/f )
  NS IN query boa matching-rrs [ empty? ] [ drop f ] [ ] 1if ;

: name->delegates ( name -- rrs-ns )
    {
      [ "" =    { } and ]
      [ is-soa? { } and ]
      [ have-ns? ]
      [ cdr-name name->delegates ]
    }
  1|| ;

: have-delegates ( message -- message/f )
  dup message-query name>> name->delegates ! message rrs-ns
  [ empty? ]
    [ 2drop f ]
    [
      dup [ rdata>> A IN query boa matching-rrs ] map concat
                                           ! message rrs-ns rrs-a
      [ >>authority-section ]
      [ >>additional-section ]
      bi*
    ]
  1if ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! outsize-zones
! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

: outside-zones ( message -- message/f )
  dup message-query name>> name->zone f =
    [ ]
    [ drop f ]
  if ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! is-nx
! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

: is-nx ( message -- message/f )
  [ message-query name>> records [ name>> = ] with filter empty? ]
    [
      NAME-ERROR >>rcode
      dup
        message-query name>> name->zone SOA IN query boa matching-rrs
      >>authority-section
    ]
    [ drop f ]
  1if ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

: none-of-type ( message -- message )
  dup
    message-query name>> name->zone SOA IN query boa matching-rrs
  >>authority-section ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

: find-answer ( message -- message )
    {
      [ have-answers   ]
      [ have-delegates ]
      [ outside-zones  ]
      [ is-nx          ]
      [ none-of-type   ]
    }
  1|| ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

: (socket) ( -- vec ) V{ f } ;

: socket ( -- socket ) (socket) 1st ;

: init-socket-on-port ( port -- )
  f swap <inet4> <datagram> 0 (socket) as-mutate ;

: init-socket ( -- ) 53 init-socket-on-port ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

: loop ( -- )
  socket receive
  swap
  parse-message
  find-answer
  message->ba
  swap
  socket send
  loop ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

: start ( -- ) init-socket loop ;

! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

MAIN: start