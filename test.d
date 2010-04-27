module test;

//import tuple_tie;
import tag_union;

void main(){}


/+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

alias TEMP = Tuple!(temp.Temp);
alias BIN  = Tuple!(BinOp, Exp, Exp);
alias ESEQ = Tuple!(Stm, Exp);

Union!(..., TEMP, BIN, ..., ESEQ) Exp;

Exp exp = ESEQ()


構造化された値を持つEnum、
(tupleを返すようにすれば、tieとの組み合わせでパターンマッチも1階層だけならうまくいく)

パターンは内部にrefの引数かワイルドカードを持つ
ワイルドカードの場合はその旨を返り値の型として記述できないか？

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++/
