class HomeController < ApplicationController
  allow_unauthenticated_access if respond_to?(:allow_unauthenticated_access)

  def index
  end
end
