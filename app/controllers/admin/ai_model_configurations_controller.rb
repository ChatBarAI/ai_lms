class Admin::AiModelConfigurationsController < Admin::BaseController
  before_action :set_configuration, only: [ :edit, :update, :destroy ]

  def index
    @configurations = AiModelConfiguration.order(:name)
  end

  def new
    defaults = AiModelConfiguration::PROVIDERS.fetch("openai")
    @configuration = AiModelConfiguration.new(
      provider: "openai", model: defaults.fetch(:default_model), base_url: defaults.fetch(:base_url)
    )
  end

  def create
    @configuration = AiModelConfiguration.new(configuration_params.merge(created_by: current_user))
    if @configuration.save
      redirect_to admin_ai_model_configurations_path, notice: "AI model configuration created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attributes = configuration_params
    attributes = attributes.except(:api_key) if attributes[:api_key].blank?
    if @configuration.update(attributes)
      redirect_to admin_ai_model_configurations_path, notice: "AI model configuration updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @configuration.destroy
      redirect_to admin_ai_model_configurations_path, notice: "AI model configuration deleted.", status: :see_other
    else
      redirect_to admin_ai_model_configurations_path,
                  alert: @configuration.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private

  def set_configuration
    @configuration = AiModelConfiguration.find(params[:id])
  end

  def configuration_params
    params.require(:ai_model_configuration)
          .permit(:name, :description, :provider, :model, :api_key, :base_url, :system_prompt, :enabled,
                  :context_window_tokens, :input_cost_cents_per_million_tokens,
                  :output_cost_cents_per_million_tokens)
  end
end
