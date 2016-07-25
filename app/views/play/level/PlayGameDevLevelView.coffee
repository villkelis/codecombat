RootView = require 'views/core/RootView'

GameUIState = require 'models/GameUIState'
God = require 'lib/God'
LevelLoader = require 'lib/LevelLoader'
GoalManager = require 'lib/world/GoalManager'
ScriptManager = require 'lib/scripts/ScriptManager'
Surface = require 'lib/surface/Surface'
ThangType = require 'models/ThangType'
Level = require 'models/Level'
LevelSession = require 'models/LevelSession'
State = require 'models/State'
utils = require 'core/utils'
urls = require 'core/urls'
Course = require 'models/Course'
GameDevVictoryModal = require './modal/GameDevVictoryModal'

TEAM = 'humans'

module.exports = class PlayGameDevLevelView extends RootView
  id: 'play-game-dev-level-view'
  template: require 'templates/play/level/play-game-dev-level-view'
  
  subscriptions:
    'god:new-world-created': 'onNewWorld'

  events:
    'click #play-btn': 'onClickPlayButton'
    'click #copy-url-btn': 'onClickCopyURLButton'

  initialize: (@options, @levelID, @sessionID) ->
    @state = new State({
      loading: true
      progress: 0
    })

    @supermodel.on 'update-progress', (progress) =>
      @state.set({progress: (progress*100).toFixed(1)+'%'})
    @level = new Level()
    @session = new LevelSession()
    @gameUIState = new GameUIState()
    @courseID = @getQueryVariable 'course'
    @god = new God({ @gameUIState })
    @levelLoader = new LevelLoader({ @supermodel, @levelID, @sessionID, observing: true, team: TEAM, @courseID })
    @supermodel.setMaxProgress 1 # Hack, why are we setting this to 0.2 in LevelLoader?
    @listenTo @state, 'change', _.debounce @renderAllButCanvas

    @levelLoader.loadWorldNecessities()

    .then (levelLoader) =>
      { @level, @session, @world } = levelLoader
      @god.setLevel(@level.serialize {@supermodel, @session})
      @god.setWorldClassMap(@world.classMap)
      @goalManager = new GoalManager(@world, @level.get('goals'), @team)
      @god.setGoalManager(@goalManager)
      @god.angelsShare.firstWorld = false # HACK
      me.team = TEAM
      @session.set 'team', TEAM
      @scriptManager = new ScriptManager({
        scripts: @world.scripts or [], view: @, @session, levelID: @level.get('slug')})
      @scriptManager.loadFromSession() # Should we? TODO: Figure out how scripts work for game dev levels
      @renderAllButCanvas()
      @supermodel.finishLoading()

    .then (supermodel) =>
      @levelLoader.destroy()
      @levelLoader = null
      webGLSurface = @$('canvas#webgl-surface')
      normalSurface = @$('canvas#normal-surface')
      @surface = new Surface(@world, normalSurface, webGLSurface, {
        thangTypes: @supermodel.getModels(ThangType)
        levelType: @level.get('type', true)
        @gameUIState
        resizeStrategy: 'wrapper-size'
      })
      @listenTo @surface, 'resize', @onSurfaceResize
      worldBounds = @world.getBounds()
      bounds = [{x: worldBounds.left, y: worldBounds.top}, {x: worldBounds.right, y: worldBounds.bottom}]
      @surface.camera.setBounds(bounds)
      @surface.camera.zoomTo({x: 0, y: 0}, 0.1, 0)
      @surface.setWorld(@world)
      @scriptManager.initializeCamera()
      @renderSelectors '#info-col'
      @spells = @session.generateSpellsObject level: @level
      goalNames = (utils.i18n(goal, 'name') for goal in @goalManager.goals)
      
      course = if @courseID then new Course({_id: @courseID}) else null
      shareURL = urls.playDevLevel({@level, @session, course})
      
      @state.set({
        loading: false
        goalNames
        shareURL
      })

    .catch (e) =>
      throw e if e.stack
      @state.set('errorMessage', e.message)

  onClickPlayButton: ->
    @god.createWorld(@spells, false, true)
    Backbone.Mediator.publish('playback:real-time-playback-started', {})
    Backbone.Mediator.publish('level:set-playing', {playing: true})
    @state.set('playing', true)

  onClickCopyURLButton: ->
    @$('#copy-url-input').val(@state.get('shareURL')).select()
    @tryCopy()

  onSurfaceResize: ({height}) ->
    @state.set('surfaceHeight', height)
    
  renderAllButCanvas: ->
    @renderSelectors('#info-col', '#share-row')
    height = @state.get('surfaceHeight')
    if height
      @$el.find('#info-col').css('height', @state.get('surfaceHeight'))

  onNewWorld: (e) ->
    if @goalManager.checkOverallStatus() is 'success'
      modal = new GameDevVictoryModal({ shareURL: @state.get('shareURL') })
      @openModalView(modal)
      modal.once 'replay', @onClickPlayButton, @

  destroy: ->
    @levelLoader?.destroy()
    @surface?.destroy()
    @god?.destroy()
    @goalManager?.destroy()
    @scriptManager?.destroy()
    delete window.world # not sure where this is set, but this is one way to clean it up
    super()
