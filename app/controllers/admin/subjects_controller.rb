class Admin::SubjectsController < Admin::BaseController
  before_action :set_subject, only: [ :show, :edit, :update, :destroy ]

  def index
    @subjects = Subject.order(:name)
  end

  def show
  end

  def new
    @subject = Subject.new
  end

  def create
    @subject = Subject.new(subject_params)
    if @subject.save
      redirect_to admin_subjects_path, notice: "Subject created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @subject.update(subject_params)
      redirect_to admin_subjects_path, notice: "Subject updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @subject.destroy
    redirect_to admin_subjects_path, notice: "Subject deleted.", status: :see_other
  rescue ActiveRecord::RecordNotDestroyed => e
    redirect_to admin_subjects_path, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def set_subject
    @subject = Subject.find_by(slug: params[:id]) || Subject.find(params[:id])
  end

  def subject_params
    params.require(:subject).permit(:name, :slug, :description)
  end
end
