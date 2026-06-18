# Admin::OrganizationsController
#
# Manages the Organisation records that group users into tenants. Each
# organisation can optionally be wired to an Enterprise SSO connection in
# Kinde so that its staff can sign in via their corporate identity provider
# (e.g. Microsoft Entra ID / Azure AD, Google Workspace).
#
# SSO SETUP OVERVIEW
# ──────────────────
# 1. In the Kinde dashboard, create an Enterprise connection for the client's
#    IdP (Settings → Connections → Enterprise). Note the `conn_01…` ID.
# 2. In this admin, edit the organisation and paste the connection ID into the
#    "Kinde Connection ID" field. Set the provider label (Microsoft / Google /
#    Other) and decide whether SSO sign-in should auto-create LMS accounts.
# 3. Share the per-org sign-in URL with the client:
#       https://<app_url>/auth/org/<slug>
#    Staff bookmark this URL; it redirects them straight to their corporate
#    IdP without passing through the generic Kinde-hosted login page.
#
# ACCOUNT CREATION ON SSO SIGN-IN
# ────────────────────────────────
# When `sso_auto_enroll` is true (the default), a new User record is created
# the first time someone authenticates via the org's SSO connection. They are
# automatically assigned to this Organisation. If a User with the same email
# already exists (e.g. created earlier with a password), the Kinde credentials
# are attached to that existing account and the org is assigned if it was blank.
# The new user's role defaults to :student; admins can promote them afterwards.
#
# FUTURE MULTI-TENANCY
# ────────────────────
# Organisation assignment is already stored on User#organization_id. When
# siloing is enabled, Ability rules will be tightened to scope catalogue reads
# to the user's own organisation. No structural changes are needed at that
# point — see the TODO comment in app/models/ability.rb.
class Admin::OrganizationsController < Admin::BaseController
  before_action :set_organization, only: [ :show, :edit, :update, :destroy ]

  # Lists all organisations alphabetically.
  # The index view shows an SSO status badge for orgs that have a Kinde
  # connection configured so admins can see at a glance which are set up.
  def index
    @organizations = Organization.by_name
  end

  # Shows organisation details: membership, enrolment/completion stats, charts,
  # notes, and the Enterprise SSO panel (connection ID, provider, sign-in URL).
  def show
    @users = @organization.users.order(:email)
    @total_enrollments = @organization.enrollments.count
    @completions = @organization.progresses.completed.count
    @completion_rate = @organization.completion_rate
    # Rolling 12-week sparkline data for the charts partial
    @enrollments_per_week = @organization.enrollments.where(enrolled_at: 12.weeks.ago..)
                                          .group_by_week(:enrolled_at).count
    @completions_per_week = @organization.progresses.completed.where(completed_at: 12.weeks.ago..)
                                          .group_by_week(:completed_at).count
  end

  def new
    @organization = Organization.new
  end

  def create
    @organization = Organization.new(organization_params)
    if @organization.save
      redirect_to admin_organization_path(@organization), notice: "Organization created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # The edit form includes a dedicated SSO section at the bottom. Fields:
  #   kinde_connection_id       — the `conn_01…` ID from the Kinde dashboard.
  #                               Must be unique across organisations (enforced
  #                               by a DB partial unique index and model validation).
  #   kinde_connection_provider — display label: "microsoft", "google", or "other".
  #                               Used only for the badge shown to the admin; the
  #                               actual IdP is determined by the Kinde connection.
  #   sso_auto_enroll           — when true, authenticating via SSO creates an LMS
  #                               account automatically. When false, the user must
  #                               already have an LMS account (matched by email)
  #                               otherwise sign-in fails with "No account found —
  #                               contact your administrator".
  def edit
  end

  def update
    if @organization.update(organization_params)
      redirect_to admin_organization_path(@organization), notice: "Organization updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Destroying an organisation does NOT delete its users — they are nullified
  # (organization_id set to nil) via the `dependent: :nullify` association.
  # Their Kinde provider/uid credentials are preserved; they simply become
  # unaffiliated users until re-assigned.
  def destroy
    @organization.destroy
    redirect_to admin_organizations_path, notice: "Organization deleted.", status: :see_other
  end

  private

  # Looks up by slug first (the friendly URL segment) then falls back to
  # numeric id to keep legacy links working.
  def set_organization
    @organization = Organization.find_by(slug: params[:id]) || Organization.find(params[:id])
  end

  # Permitted parameters include the three SSO fields added in migration
  # 20260604175824. Clearing kinde_connection_id (setting it to blank) will
  # disable SSO for the org — the /auth/org/:slug route will return a
  # "not configured" error rather than attempting a Kinde redirect.
  def organization_params
    params.require(:organization).permit(:name, :slug, :contact_email, :notes,
                                         :kinde_connection_id, :kinde_connection_provider,
                                         :sso_auto_enroll, :sso_required, :sso_domain)
  end
end
