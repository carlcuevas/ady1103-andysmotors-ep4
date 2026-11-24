terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
  # Sin default_tags a proposito: en la EP4 las etiquetas se aplican con
  # Tag Editor (evidencia de la seccion 4) y luego se auditan por CLI.
}
