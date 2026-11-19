// Strumento di build (mai distribuito): estende `sip_grammar.belr` con
// `param-unreserved =/ %x22` per tollerare parametri URI con virgolette
// (es. `Contact: <sip:...;thinfo="...">` emesso da proxy SBC Yeastar/OpenSIPS)
// evitando il rifiuto 481 sui NOTIFY BLF in belle-sip.
#include <iostream>
#include <memory>
#include <belr/belr.h>
#include <belr/grammarbuilder.h>

int main(int argc, char** argv) {
  if (argc != 3) {
    std::cerr << "Uso: patch_sip_grammar <input.belr> <output.belr>\n";
    return 2;
  }
  auto base = std::make_shared<belr::Grammar>("sip");
  if (base->load(argv[1]) != 0) {
    std::cerr << "Impossibile caricare la grammatica: " << argv[1] << "\n";
    return 1;
  }
  belr::ABNFGrammarBuilder builder;
  auto patched = builder.createFromAbnf("param-unreserved =/ %x22\r\n", base);
  if (!patched) {
    std::cerr << "Impossibile estendere param-unreserved\n";
    return 1;
  }
  patched->optimize();
  if (patched->save(argv[2]) != 0) {
    std::cerr << "Impossibile salvare la grammatica: " << argv[2] << "\n";
    return 1;
  }
  return 0;
}
