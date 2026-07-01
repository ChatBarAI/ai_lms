// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

import "trix"
import "@rails/actiontext"
import "trix_config"

const isSecureContextHost =
	window.location.protocol === "https:" ||
	window.location.hostname === "localhost" ||
	window.location.hostname === "127.0.0.1"

if ("serviceWorker" in navigator && isSecureContextHost) {
	window.addEventListener("load", () => {
		navigator.serviceWorker.register("/service-worker", { scope: "/" }).catch((error) => {
			// Keep registration failure non-fatal to page rendering.
			console.error("Service worker registration failed", error)
		})
	})
}
