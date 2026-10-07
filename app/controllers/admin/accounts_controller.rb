# frozen_string_literal: true

module Admin
  class AccountsController < BaseController
    def new
    end

    def create
      @account = PreparedAccountCreator.call(
        daily_nap_count: params[:daily_nap_count],
        naps_taken: params[:naps_taken]
      )
      render :create
    rescue PreparedAccountCreator::Error => e
      flash.now[:alert] = e.message
      render :new, status: :unprocessable_entity
    end
  end
end
