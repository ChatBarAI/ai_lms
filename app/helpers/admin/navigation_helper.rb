module Admin::NavigationHelper
  # Lucide icon paths (24x24, stroked) used by the admin sidebar.
  ADMIN_NAV_ICONS = {
    dashboard: "M3 3h7v9H3zM14 3h7v5h-7zM14 12h7v9h-7zM3 16h7v5H3z",
    subjects: "M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z",
    courses: "M12 7v14M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z",
    tags: "M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42zM7.5 7.5h.01",
    certificates: "m15.477 12.89 1.515 8.526a.5.5 0 0 1-.81.47l-3.58-2.687a1 1 0 0 0-1.197 0l-3.586 2.686a.5.5 0 0 1-.81-.469l1.514-8.526M18 8A6 6 0 1 1 6 8a6 6 0 0 1 12 0Z",
    users: "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75",
    marking: "M9 2h6a1 1 0 0 1 1 1v2a1 1 0 0 1-1 1H9a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1ZM16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2M9 14l2 2 4-4",
    ai_models: "M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0zM20 3v4M22 5h-4",
    settings: "M21 4h-7M10 4H3M21 12h-9M8 12H3M21 20h-5M12 20H3M14 2v4M8 10v4M16 18v4",
    back: "M19 12H5M12 19l-7-7 7-7",
    sign_out: "M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9",
    menu: "M4 6h16M4 12h16M4 18h16",
    close: "M18 6 6 18M6 6l12 12"
  }.freeze

  # Sections of the admin sidebar. `controllers` lists the admin controllers an item is
  # highlighted for, so nested pages (lessons under a module, organisations under users)
  # keep their parent item active.
  def admin_nav_sections
    [
      { items: [
        { label: "Dashboard", path: admin_root_path, icon: :dashboard, controllers: %w[dashboard] }
      ] },
      { heading: "Content", items: [
        ({ label: terms[:subjects], path: admin_subjects_path, icon: :subjects, controllers: %w[subjects] } if subjects_enabled?),
        { label: terms[:courses], path: admin_courses_path, icon: :courses, controllers: %w[courses lessons] },
        { label: "Tags", path: admin_tags_path, icon: :tags, controllers: %w[tags] },
        { label: "Certificates", path: admin_certificates_path, icon: :certificates, controllers: %w[certificates] }
      ].compact },
      { heading: "People", items: [
        { label: "Users", path: admin_users_path, icon: :users, controllers: %w[users organizations] },
        { label: "Marking", path: admin_marking_queue_path, icon: :marking, controllers: %w[marking_queue question_answers], badge: :marking }
      ] },
      { heading: "Configure", items: [
        { label: "AI models", path: admin_ai_model_configurations_path, icon: :ai_models, controllers: %w[ai_model_configurations] },
        { label: "Settings", path: edit_admin_site_setting_path, icon: :settings, controllers: %w[site_settings] }
      ] }
    ]
  end

  def admin_nav_active?(item)
    controller_path.start_with?("admin/") && item[:controllers].include?(controller_name)
  end

  def admin_nav_icon(name, size_class: "h-5 w-5")
    tag.svg(
      xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24",
      fill: "none", stroke: "currentColor",
      "stroke-width": "2", "stroke-linecap": "round", "stroke-linejoin": "round",
      class: "shrink-0 #{size_class}", "aria-hidden": "true"
    ) { tag.path(d: ADMIN_NAV_ICONS.fetch(name)) }
  end
end
