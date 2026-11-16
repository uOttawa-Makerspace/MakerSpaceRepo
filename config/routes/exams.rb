# frozen_string_literal: true

resources :questions do
  collection { delete :delete_individually }
  member { delete "answers/:answer_id", action: :remove_answer, as: :remove_answer }
end

resources :exams, only: %i[index show destroy] do
  collection do
    post :finish_exam
    post :create_from_training
    post :create_for_single_user
  end
end

resources :exam_responses, only: [:create]
