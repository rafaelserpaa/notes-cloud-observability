# Regras do tflint (buildspecs/iac.yml). O plugin "terraform" vem embutido no
# binário: nada é baixado na execução.
#
# Para rodar localmente, igual ao pipeline:
#   tflint --recursive --config "$PWD/.tflint.hcl" --format compact
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
