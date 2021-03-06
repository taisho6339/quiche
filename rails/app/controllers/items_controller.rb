class ItemsController < ApplicationController
  before_action :set_item, only: [:show, :edit, :update, :destroy]

  include ApplicationHelper
  def index
    user = User.where("last_name = ? or twitter_id = ?", params[:query], params[:query])
    result = Item.search do
      if (user.blank?)
        fulltext params[:query]
      else
        with(:user_id, user.first.id)
      end
      order_by :created_at, :desc
      Sunspot.config.pagination.default_per_page = 50
    end
    @items = result.results
  end

  def show
  end

  def new
    @item = Item.new
  end

  def edit
  end

  def create
    require 'open-uri'
    uri = URI params[:url]
    source = open(uri).read
    obj = Readability::Document.new(source, encoding: source.encoding.to_s)

    title = obj.title
    content_html = obj.content.encode('UTF-8')
    images = obj.images

    # TODO Avoid using direct link
    unless images.empty?
      if  ( (images[0] =~ /^\//) == 0) # relative path
        images[0] = 'http://' + uri.host + images[0]
      elsif ( (images[0] =~ /^http/) != 0) # filename only
        images[0] = 'http://' + uri.host + uri.path + images[0]
      end
    else
      screen_shot_binary = IMGKit.new(params[:url], width: 144).to_img(:jpg)
    end

    twitter_id = params[:user][:quiche_twitter_id]
    image_url = params[:user][:quiche_twitter_image_url]

    if ( ( user = User.find_by(twitter_id: twitter_id) ) == nil )
      message = 'Create user in "Oven" before Baking!' # chrome extention で表示
    elsif ( item = Item.find_by(title: title) ) # 既に読まれていた場合
      if Reader.create({user: user, item: item}) # user を reader に追加
        message = 'Your Quiche has also baked!'
      end
    else
      @item = Item.new({
        title: title,
        url: params[:url],
        content: content_html,
        first_image_url: images[0],
        screen_shot: screen_shot_binary,
        user_id: User.find_by(twitter_id: twitter_id).id
        })
      if @item.save
        message = 'success'
        bitly = Bitly.new(ENV['bitly_legacy_login'], ENV['bitly_legacy_api_key'])
        tweet('['+title.truncate(108) + '] が焼けたよ ' + bitly.shorten(params[:url]).short_url)
      else
        format.json { render json: @item.errors, status: :unprocessable_entity }
      end
    end
    respond_to do |format|
      format.json {
        render json: {
          action: 'add',
          result: message,
        }
      }
    end
  end

  def update
    respond_to do |format|
      if @item.update(item_params)
        format.html { redirect_to @item, notice: 'Item was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @item.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @item.destroy
    respond_to do |format|
      format.html { redirect_to '/' }
      format.json { head :no_content }
    end
  end

  def get_image
    send_data(Item.find(params[:id]).screen_shot, filename: "#{Item.find(params[:id])}.jpg", :disposition => 'inline' , type: 'image/jpeg')
  end

  private
    def set_item
      @item = Item.find(params[:id])
    end

    def item_params
      params.require(:item).permit(:title, :first_image_url, :user_id, :name, :content, :deleted_at)
    end

    def tweet(tweet_content)
        require 'twitter'
        client = Twitter::REST::Client.new do |config|
          config.consumer_key       = ENV['consumer_key']
          config.consumer_secret    = ENV['consumer_secret']
          config.access_token        = ENV['oauth_token']
          config.access_token_secret = ENV['oauth_token_secret']
        end
        tweet_content = (tweet_content.length > 140) ? tweet_content[0..139].to_s : tweet_content
      begin
        client.update(tweet_content)
      rescue Exception => e
        p e
      end
    end
end
