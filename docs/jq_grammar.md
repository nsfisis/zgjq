# Jq Grammar


## Notation

* `'A'`: Terminal symbol
* `A`: Non-terminal symbol
* `A / B`: A or B
* `A?`: Optional A
* `{ A }+`: 1 or more repetitions of A
* `{ A }*`: 0 or more repetitions of A
* `{ A | S }+`: 1 or more repetitions of A separated by S
    * Equivalent to `A { S A }*`
* `{ A | S }*`: 0 or more repetitions of A separated by S
    * Equivalent to `{ A | S }+?`
* `{ A |? S }+`: 1 or more repetitions of A separated by S, allowing optional trailing S
    * Equivalent to `A { S A }* S?`
* `{ A |? S }*`: 1 or more repetitions of A separated by S, allowing optional trailing S
    * Equivalent to `{ A |? S }+?`
* `( A )`: Grouping
* `# ...`: Additional constraints


## Grammar

```
program:
    module? imports body

module:
    'module' query ';'

imports:
    { import }+

import:
    'import' STRING 'as' BINDING query? ';'
    'import' STRING 'as' IDENT query? ';'
    'include' STRING query? ';'

body:
    funcdefs
    query

funcdefs:
    { funcdef }+

funcdef:
    'def' IDENT ':' query ';'
    'def' IDENT '(' params ')' ':' query ';'

params:
    { param | ';' }+

param:
    BINDING
    IDENT

query:
    funcdef query
    expr 'as' patterns '|' query
    'label' BINDING '|' query
    query2

query2:
    query3 '|' query3
    query3

query3:
    expr ',' expr
    expr

expr:
    expr2 '//' expr2
    expr2

expr2:
    expr3 '=' expr3
    expr3 '|=' expr3
    expr3 '//=' expr3
    expr3 '+=' expr3
    expr3 '-=' expr3
    expr3 '*=' expr3
    expr3 '/=' expr3
    expr3 '%=' expr3
    expr3

expr3:
    expr4 'or' expr4
    expr4

expr4:
    expr5 'and' expr5
    expr5

expr5:
    expr6 '==' expr6
    expr6 '!=' expr6
    expr6 '<' expr6
    expr6 '>' expr6
    expr6 '<=' expr6
    expr6 '>=' expr6
    expr6

expr6:
    expr7 '+' expr7
    expr7 '-' expr7
    expr7

expr7:
    term '*' term
    term '/' term
    term '%' term
    term

term:
    '.'
    '..'
    'break' BINDING
    term FIELD '?'
    FIELD '?'
    term '.' STRING '?'
    '.' STRING '?'
    term FIELD
    FIELD
    term '.' STRING
    '.' STRING
    term '[' query ']' '?'
    term '[' query ']'
    term '.' '[' query ']' '?'
    term '.' '[' query ']'
    term '[' ']' '?'
    term '[' ']'
    term '.' '[' ']' '?'
    term '.' '[' ']'
    term '[' query ':' query ']' '?'
    term '[' query ':' ']' '?'
    term '[' ':' query ']' '?'
    term '[' query ':' query ']'
    term '[' query ':' ']'
    term '[' ':' query ']'
    term '?'
    LITERAL
    STRING
    FORMAT
    '-' term
    '(' query ')'
    '[' query ']'
    '[' ']'
    '{' dict-pairs '}'
    'reduce' expr 'as' patterns '(' query ';' query ')'
    'foreach' expr 'as' patterns '(' query ';' query ';' query ')'
    'foreach' expr 'as' patterns '(' query ';' query ')'
    'if' query 'then' query else-body
    'try' expr 'catch' expr
    'try' expr
    '$' '$' '$' BINDING
    BINDING
    '$__loc__'
    IDENT
    IDENT '(' args ')'

else-body:
    'elif' query 'then' query else-body
    'else' query 'end'
    'end'

args:
    { query | ';' }+

rep-patterns:
    { pattern | '?//' }

patterns:
    { pattern | '?//' }

pattern:
    BINDING
    '[' array-patterns ']'
    '{' obj-patterns '}'

array-patterns:
    { pattern | ',' }

obj-patterns:
    { obj-pattern | ',' }

obj-pattern:
    BINDING
    BINDING ':' pattern
    IDENT ':' pattern
    KEYWORD ':' pattern
    STRING ':' pattern
    '(' query ')' ':' pattern

dict-pairs:
    { dict-pair | ',' }*

dict-pair:
    IDENT ':' dict-expr
    KEYWORD ':' dict-expr
    STRING ':' dict-expr
    STRING
    BINDING ':' dict-expr
    BINDING
    IDENT
    "$__loc__"
    KEYWORD
    '(' query ')' ':' dict-expr

dict-expr:
    { expr | '|' }
```
