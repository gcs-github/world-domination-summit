_ = require('underscore')
redis = require("redis")
rds = redis.createClient()
twitterAPI = require('node-twitter-api')
moment = require('moment')
crypto = require('crypto')
async = require('async')

routes = (app) ->

	[Event, Events] = require('../../models/events')
	[EventHost, EventHosts] = require('../../models/event_hosts')
	[EventRsvp, EventRsvps] = require('../../models/event_rsvps')
	[EventInterest, EventInterests] = require('../../models/event_interests')
	[User, Users] = require('../../models/users')

	event =
		add: (req, res, next) ->
			if req.me
				post = _.pick req.query, Event::permittedAttributes
				start = moment.utc(process.year+'-07-'+req.query.date+' '+req.query.hour+':'+req.query.minute+':00', 'YYYY-MM-DD HH:mm:ss')
				if req.query.hour is '12'
					req.query.pm = Math.abs(req.query.pm - 12)
				post.start = start.add('hours', req.query.pm).format('YYYY-MM-DD HH:mm:ss')

				if not post.type?
					post.type = 'meetup'

				post.year = process.yr

				Event.forge(post)
				.save()
				.then (event) ->
					if post.type is 'meetup'
						EventHost.forge({event_id: event.get('event_id'), user_id: req.me.get('user_id')})
						.save()
						.then (host) ->
							if req.query.interests? and req.query.interests.length
								async.each req.query.interests.split(','), (interest, cb) ->
									EventInterest.forge({event_id: event.get('event_id'), interest_id: interest})
									.save()
									.then (interest) ->
										cb()
								, ->
									next()
							else
								next()
						, (err) ->
							console.error(err)
					else
						next()
				, (err) ->
					console.error(err)
			else
				res.r.msg = 'You\'re not logged in!'
				res.status(401)
				next()

		upd: (req, res, next) ->
			if req.me
				post = _.pick req.query, Event::permittedAttributes
				start = moment.utc(process.year+'-07-'+req.query.date+' '+req.query.hour+':'+req.query.minute+':00', 'YYYY-MM-DD HH:mm:ss')
				if req.query.hour is '12'
					req.query.pm = Math.abs(req.query.pm - 12)
				post.start = start.add('hours', req.query.pm).format('YYYY-MM-DD HH:mm:ss')
				Event.forge({event_id: post.event_id})
				.fetch()
				.then (ev) ->
					EventHost.forge({event_id: post.event_id, user_id: req.me.get('user_id')})
					.fetch()
					.then (host) ->
						if not host
							req.me.getCapabilities()
							.then ->
								if req.me.hasCapability('schedule')
									ev.set(post)
									.save()
									.then ->
										next()
								else
									res.r.msg = 'You don\'t have permission to do that!'
									res.status(403)
									next()
						else
								ev.set(post)
								.save()
								.then ->
									next()
			else
				res.r.msg = 'You don\'t have permission to do that!'
				res.status(403)
				next()

		del: (req, res, next) ->
			if req.me? && req.me.hasCapability('schedule')
				if req.query.feed_id?
					Feed.forge req.query.feed_id
					.fetch()
					.then (feed) ->
						if feed.get('user_id') is req.me.get('user_id')
							feed.destroy()
							.then ->
								next()
				else
					res.r.msg = 'No feed item sent'
					res.status(400)
					next()
			else
				res.status(401)
				next()

		get: (req, res, next) ->
			if req.me.hasCapability('schedule')
				events = Events.forge()
				limit = req.query.per_page ? 500
				page = req.query.page ? 1
				if req.query.active?
					active = req.query.active
					events.query('where', 'active', active)
				if req.query.type?
					events.query('where', 'type', req.query.type)
				if req.query.event_id
					events.query('where', 'event_id', req.query.event_id)
				events.query('orderBy', 'event_id',  'DESC')
				events.query('limit', limit)
				events.query('where', 'ignored', 0)
				events
				.fetch()
				.then (events) ->
					evs = []
					async.each events.models, (ev, cb) ->
						tmp = ev.attributes
						tmp.hosts = []
						start = (tmp.start+'').split(' GMT')
						start = moment(start[0])
						tmp.start = start.format('YYYY-MM-DD HH:mm:ss')
						EventHosts.forge()
						.query('where', 'event_id', '=', tmp.event_id)
						.fetch()
						.then (rsp) ->
							for host in rsp.models
								tmp.hosts.push(host.get('user_id'))
							evs.push(tmp)
							cb()
					, ->
						res.r.events = evs
						next()
			else
				res.status(401)
				next()

		accept: (req, res, next) ->
			if req.me.hasCapability('schedule')
				Event.forge
					event_id: req.query.event_id
				.fetch()
				.then (model) ->
					EventHost.forge({event_id: req.query.event_id})
					.fetch()
					.then (host) ->
						User.forge({user_id: host.get('user_id')})
						.fetch()
						.then (host) ->
							host.sendEmail('meetup-approved', 'Thanks for your meetup proposal!')
							model.set('active', 1)
							model.save()
							next()
			else
				res.status(401)
				next()

		reject: (req, res, next) ->
			if req.me.hasCapability('schedule')
				Event.forge
					event_id: req.query.event_id
				.fetch()
				.then (model) ->
					EventHost.forge({event_id: req.query.event_id})
					.fetch()
					.then (host) ->
						User.forge({user_id: host.get('user_id')})
						.fetch()
						.then (host) ->
		#					host.sendEmail('meetup-declined', 'Thanks for your meetup proposal!')
							model.set('ignored', 1)
							model.save()
							next()
				, (err) ->
					console.error(err)
			else
				res.status(401)
				next()

		get_attendees: (req, res, next) ->
			EventRsvps.forge()
			.query('where', 'event_id', '=', req.query.event_id)
			.fetch()
			.then (rsp) ->
				atns = []
				for atn in rsp.models
					atns.push(atn.get('user_id'))
				res.r.attendees = atns
				next()
			, (err) ->
				console.err(err)

		rsvp: (req, res, next) ->
			event_id = req.query.event_id
			if req.me
				rsvp = EventRsvp.forge({user_id: req.me.get('user_id'), event_id: event_id})
				rsvp	
				.fetch()
				.then (existing) ->
					if existing
						res.r.action = 'cancel'
						existing.destroy()
						.then ->
							finish()
					else
						res.r.action = 'rsvp'
						rsvp.save()
						.then ->
							finish()

					finish = ->
						EventRsvps.forge()
						.query('where', 'event_id', event_id)
						.fetch()
						.then (rsp) ->
							Event.forge
								event_id: event_id
								num_rsvps: rsp.models.length
							.save()
						next()

module.exports = routes
