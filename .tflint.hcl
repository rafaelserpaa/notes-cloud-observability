# Regras do tflint (buildspecs/iac.yml). O plugin "terraform" vem embutido no
# binário: nada é baixado na execução.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
