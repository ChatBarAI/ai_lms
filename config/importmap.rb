# Pin npm packages by running ./bin/importmap

pin "application"
pin "actiontext_editor"
pin "actioncable", to: "actioncable.esm.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "trix" # @2.1.19
pin "@rails/actiontext", to: "@rails--actiontext.js" # @8.1.300
pin "trix_config", to: "trix_config.js"
