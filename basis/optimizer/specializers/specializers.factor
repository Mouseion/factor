! Copyright (C) 2006, 2008 Slava Pestov.
! See http://factorcode.org/license.txt for BSD license.
USING: accessors arrays generic hashtables kernel kernel.private
math namespaces sequences vectors words strings layouts
combinators sequences.private classes generic.standard
generic.standard.engines assocs ;
IN: optimizer.specializers

: (make-specializer) ( class picker -- quot )
    swap "predicate" word-prop append ;

: make-specializer ( classes -- quot )
    dup length <reversed>
    [ (picker) 2array ] 2map
    [ drop object eq? not ] assoc-filter
    dup empty? [ drop [ t ] ] [
        [ (make-specializer) ] { } assoc>map
        unclip [ swap [ f ] \ if 3array append [ ] like ] reduce
    ] if ;

: specializer-cases ( quot word -- default alist )
    dup [ array? ] all? [ 1array ] unless [
        [ make-specializer ] keep
        [ declare ] curry pick append
    ] { } map>assoc ;

: method-declaration ( method -- quot )
    dup "method-generic" word-prop dispatch# object <array>
    swap "method-class" word-prop prefix ;

: specialize-method ( quot method -- quot' )
    method-declaration [ declare ] curry prepend ;

: specialize-quot ( quot specializer -- quot' )
    specializer-cases alist>quot ;

: standard-method? ( method -- ? )
    dup method-body? [
        "method-generic" word-prop standard-generic?
    ] [ drop f ] if ;

: specialized-def ( word -- quot )
    dup def>> swap {
        { [ dup standard-method? ] [ specialize-method ] }
        {
            [ dup "specializer" word-prop ]
            [ "specializer" word-prop specialize-quot ]
        }
        [ drop ]
    } cond ;

: specialized-length ( specializer -- n )
    dup [ array? ] all? [ first ] when length ;