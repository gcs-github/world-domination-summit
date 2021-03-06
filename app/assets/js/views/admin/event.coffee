ap.Views.admin_event = XView.extend
	ticketTimo: 0
	events: 
		'submit #admin-event-update': 'event_submit'
	initialize: ->
		theEvent = false
		ap.api 'get admin/schedule', {}, (rsp) =>
			events = rsp.events
			for ev in events
				if +ev.event_id is +@options.extra
					theEvent = ev
			@options.out = _.template @options.out, theEvent
			@event = theEvent
			@initRender()

	rendered: ->
		start = moment.utc(@event.start)
		window.start = start
		hour = start.format('HH')
		pm = 0
		if hour >= 12
			if hour > 12
				hour -= 12
			if hour < 10
				hour = '0'+hour
			pm = 12
		if hour is '00'
			hour = '12'
		$('select[name="date"]').select2('val', start.format('DD'))
		$('select[name="hour"]').select2('val', hour)
		$('select[name="minute"]').select2('val', start.format('mm'))
		$('select[name="pm"]').select2('val', pm)
		$('select[name="active"]').select2('val', @event.active)

	event_submit: (e) ->
		e.preventDefault()
		el = $(e.currentTarget)
		btn = _.btn($('.button', el), 'Saving...', 'Saved!')
		form = el.formToJson()
		ap.api 'put event', form, (rsp) ->
			#ap.schedule = rsp.schedule
			btn.finish()
			ap.navigate('admin/schedule')
