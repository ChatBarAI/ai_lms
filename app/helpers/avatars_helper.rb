module AvatarsHelper
  # A user's round avatar: their uploaded image, else the image from their
  # sign-in provider, else the first letter of their display name.
  #
  # size_class sets the box (e.g. "w-7 h-7"); initial_class sets the letter's
  # font size for the fallback. Pass full Tailwind class strings so the
  # Tailwind scanner can see them in the calling view.
  def user_avatar_tag(user, size_class:, initial_class:)
    image_classes = "#{size_class} rounded-full object-cover border border-gray-200"

    if user.avatar.attached?
      image_tag image_variant(user.avatar, :avatar), class: image_classes
    elsif user.image_url.present?
      image_tag user.image_url, class: image_classes
    else
      tag.div user.display_name.first.upcase,
              class: "#{size_class} #{initial_class} rounded-full bg-indigo-100 flex items-center justify-center text-indigo-600 font-bold"
    end
  end
end
