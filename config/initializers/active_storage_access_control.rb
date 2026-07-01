# Wire the ActiveStorageAccessControl concern into Rails' built-in Active
# Storage controllers. The concern contains the actual authorization policy; this
# initializer makes sure blob downloads, image/video/PDF representations, and
# direct uploads all run through it.
#
# to_prepare runs on boot and on each code reload in development. The include
# guard keeps the concern from being included repeatedly.
Rails.application.config.to_prepare do
  [
    ActiveStorage::Blobs::RedirectController,
    ActiveStorage::Blobs::ProxyController,
    ActiveStorage::Representations::RedirectController,
    ActiveStorage::Representations::ProxyController,
    ActiveStorage::DirectUploadsController
  ].each do |controller|
    controller.include ActiveStorageAccessControl unless controller < ActiveStorageAccessControl
  end
end
