terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "2.11.0"
    }
    github = {
      source = "integrations/github"
      version = "5.12.0"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

provider "github" {
   token = ""
   owner = ""
}

locals {
  users_configuration_json = jsondecode(file("${path.module}/configs/users-configuration.json"))

  users_configuration_combinations = distinct(flatten([
    for cfg in local.users_configuration_json : [ # Проходимся по пользователям
      for mdl in cfg.modules : { # Модули пользователя
        module    = mdl
        user      = cfg.user
        server    = cfg.server
        namespace = cfg.namespace
      }
    ]
  ]))

  dbs = distinct(flatten([
    for cfg in local.users_configuration_json : [ # Проходимся по пользователям
      for mdl in cfg.modules : [ # Модули пользователя
        for app in fileset("${path.module}/../apps/${mdl}", "**/*.json") : [ # Поиск всех приложений в папке
          for db in (jsondecode(file("${path.module}/../apps/${mdl}/${app}"))).databases : # Проходимся по базам данных приложения
          {
            namespace = cfg.namespace 
            module    = mdl
            user      = cfg.user
            dbname    = db
          }
        ]
      ]
    ]
  ]))
}

resource "kubernetes_namespace" "user_namespaces" {
  for_each = { for u in local.users_configuration_json : u.namespace => u.namespace}
  metadata {
    name = each.value
  }
}

resource "github_repository_file" "module_setup" {
  for_each = { for t in local.users_configuration_combinations : "${t.user} ${t.module}" => t }
  repository          = "argocd-module-saas-test"
  branch              = "main"
  file                = "cluster-config/${each.value.module}/${each.value.user}.json"
  content             = jsonencode({"destination" = {"server"= each.value.server, "namespace" = each.value.namespace}} )
  commit_message      = "Managed by Terraform"
  commit_author       = "Terraform User"
  commit_email        = "terraform@example.com"
  overwrite_on_create = true
}


module "postgresql" {
  for_each = { for t in local.dbs : "${t.user} ${t.module} ${t.dbname} " => t }
  source        = "ballj/postgresql/kubernetes"
  version       = "~> 1.2"
  namespace     = each.value.namespace
  object_prefix = "${each.value.user}-${each.value.module}-${each.value.dbname}"
  name = each.value.dbname
}
