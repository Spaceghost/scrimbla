# disabling logs for now
# console:log = do true
extern requestAnimationFrame

var OPEN = ['"',"'",'(','[','{','<']
var CLOSE = ['"',"'",')',']','}','>']

if Imba.Events
	Imba.Events.register(['copy','paste','cut','beforecut','beforepaste','beforecopy','keypress'])

import Logger from './core/logger'
import History from './core/history'
import Buffer from './core/buffer'
import Observer from './core/observer'

import Region from './region'
import Hints,Hint from './core/hints'
import Highlighter from './core/highlighter'

import './core/util' as util

require './core/caret'

require './views/overlays'

tag imdims

	def ch
		# uncache
		if @ow != dom:offsetWidth
			@ow = dom:offsetWidth
			@ch = null

		@ch ||= dom.getBoundingClientRect:width

tag imviewbody

tag imview

	prop filename

	prop observer
	prop history
	prop hints
	prop logger
	prop shortcuts
	prop focusNode watch: yes
	prop caret
	prop frames
	prop readonly

	def highlighter
		Highlighter

	def lineHeight
		@dims.dom:offsetHeight

	def charWidth
		@dims.ch

	def isReadOnly
		history.mode == 'play'

	def tabSize
		4

	def build
		# console.log 'build imview'
		VIEW = self
		tabindex = 0

		@readonly = no
		@logger = Logger.new(self)
		@frames = 0
		@changes = 0
		
		@hints    = Hints.new(self)
		@buffer    = Buffer.new(self)
		@history   = History.new(self)
		@shortcuts = ShortcutManager.new(self)
		render
		@observer  = Observer.new(self)
		caret.region = Region.new(0,0,root,self)

		# bind to mousemove of dom?

		dom.addEventListener('mouseover') do |e| Imba.Events.delegate(e)
		dom.addEventListener('mouseout') do |e| Imba.Events.delegate(e)
		input ||= IM.captor
		self

	def onmouseover e
		e.halt

	def onmouseout e
		e.halt

	def input= input

		if input != @input
			@input = input
			# console.log 'set input!!!',@input
			@input.dom:_responder = dom
		self

	def input
		@input or @caret.input

	# called every frame - looking for changed nodes to deal with
	# to deal with mutations.
	def tick
		@frames++
		history.tick
		render
		repair if @dirty
		self

	def commit
		tick

	def log
		logger.log(*arguments)
		self

	def edited
		@changes++
		@dirty = yes
		@buffer.refresh

		view.hints.rem do |hint|
			hint.group == 'runtime'

		hints.cleanup

		delay('didchange',50) do
			Imba.Events.trigger('edited:async',self,data: self)

		# we can improve how/when we choose to annotate.
		# currently we do it after every edit - but it should
		# really only be needed when we have changed identifiers.
		# should also only reannotate the closest known scope,
		# but this comes later with refactoring from whole files
		# to scopes.
		delay('annotate',500) do annotate
		delay('recompile',-1) # cancel recompilation
		self

	def dirty
		self

	def activate
		flag(:active)
		self

	def deactivate
		unflag(:active)
		self

	def body
		<imviewbody@body>
			<imdims@dims> "x"
			<imcaret@caret view=self>
			<imroot@root.imba view=self>

	def header
		null

	def footer
		null

	def overlays
		<scrimbla-overlays@overlays view=self>

	def render
		<self .readonly=isReadOnly>
			header
			body
			footer

	def view
		self
		
	def sel
		caret

	def root
		@root

	def buffer
		@buffer
		# root.code
		
	def size
		root.size

	def load code, o = {}
		filename = o:filename
		# console.log 'loading file with filename',o:filename
		# observer.pause do
		if o:html
			root.dom:innerHTML = o:html
			@buffer.refresh
			history.onload(self.code)
		else
			# should use our new parser
			if var parsed = parse(code)
				if parsed:highlighted
					root.dom:innerHTML = parsed:highlighted
				else
					root.dom:textContent = code
			@buffer.refresh
			history.onload(code)
			annotate
		self

	def parse code
		# here we can parse the full code
		{highlighted: IM.parse(code)}

	def refocus
		input.focus unless document:activeElement == input.dom
		self

	def oninputfocus e
		console.log 'oninputfocus!!'
		VIEW = self # hack
		flag('focus')

	def oninputblur e
		unflag('focus')

	def onfocusin e
		VIEW = self # hack
		flag('focus')
		console.log 'focus',e
		self

	def onfocusout e
		unflag('focus')
		console.log 'unfocus',e
		self

	def oninput e
		self

	def ontextinput e
		self

	def execAction action, keydown
		if action:command isa Function
			action:command.call(self,caret,action:data or {event: keydown},self)
		elif action:command isa String
			log 'command is string',action:command
			var ev = Imba.Events.trigger(action:command,self,data: action)
			log ev
			self

	def tryCommand cmd, target, params = []
		if cmd:context
			let guard = cmd:context.apply(target or self,params)
			return no unless guard

		if cmd:command isa Function
			return cmd:command.apply(target or self,params)



	def onkeydown e
		VIEW = self # hack
		e.halt
		# var combo = e.keycombo
		var combo = shortcuts.keysForEvent(e.event)
		var action = shortcuts.getShortcut(e)
		var ins = null

		var shift = (/\bshift\b/).test(combo)
		var alt = (/\balt\b/).test(combo)
		var sup = (/\bsuper\b/).test(combo)

		# log 'imview keydown',combo

		if action
			# console.log 'action here?!',action
			e.cancel if execAction(action,e)
			return

		# move these into commands as well
		# thisshould move this into commands instead
		if let arr = combo.match(/\b(left|right|up|down)/)
			hints.activate

			let isCollapsed = caret.isCollapsed
			let ends = caret.ends

			shift ? caret.decollapse : caret.collapse

			if arr[0] == 'down'
				caret.moveDown
				return e.cancel

			elif arr[0] == 'up'
				caret.moveUp
				return e.cancel

			let mode = IM.CHARACTERS
			let dir = 0

			if arr[0] == 'left'
				dir = -1

			if arr[0] == 'right'
				dir = 1

			if alt
				mode = dir > 0 ? IM.WORD_END : IM.WORD_START

			elif sup
				mode = dir > 0 ? IM.LINE_END : IM.LINE_START

			elif !shift and !isCollapsed
				caret.head.set(dir > 0 ? ends[1] : ends[0])
				caret.dirty # should not need to call this all the time
				return e.cancel

			caret.move(dir,mode)

			return e.cancel

		if e.event:which == 229
			return e.halt

		if combo.match(/^super\+(c|v|x)$/)
			# console.log 'matching combo for copy paste'
			e.halt
			@awaitCombo = yes
			refocus
			return

		if ins != null
			e.halt.cancel
			caret.insert(ins)
			return self

		self

	def onkeypress e
		if @awaitCombo
			@awaitCombo = no
			return e.halt

		e.halt
		var text = String.fromCharCode(e.event:charCode)
		e.@text = text
		e.cancel
		ontype(e)
		self

	def ontextinput e
		e.halt.cancel
		e.@text = e.event:data
		ontype(e)
		self

	def onkeyup e
		e.halt
		self

	def oninput e
		e.halt
		self

	def ontype e
		try 
			var ins = e.@text
			# log 'ontype',e,ins

			let spans = view.nodesInRegion(caret.region,no,yes)
			let target = spans[0]
			let cmd

			if spans:length == 1
				# log 'single node for nodesInRegion',target:node
				if cmd = target:node["trigger-{ins}"]
					# log "found combo for this!??!",cmd
					if tryCommand(cmd,caret,[target:node,target])
						return self

			cmd = shortcuts.getTrigger(self,ins)

			if cmd and cmd:command isa Function
				# log 'found command!!',cmd
				# should rather run tryCommand?!?
				cmd.command(caret,self,ins,e)
			else
				caret.insert(ins) if ins
		catch e
			log 'error from ontype'

	def onbackspace e
		e.cancel.halt
		caret.erase
		return

	def onbeforecopy e
		console.log('onbeforecopy',e) if DEBUG
		input.select
		var data = e.event:clipboardData
		data.setData('text/plain', caret.text)
		e.halt

	def oncopy e
		console.log('oncopy',e,caret.text) if DEBUG
		var data = e.event:clipboardData
		data.setData('text/plain', caret.text)
		e.halt.cancel
		refocus
		return

	def oncut e
		if DEBUG
			console.log 'oncut',e
		var data = e.event:clipboardData
		data.setData('text/plain', caret.text)
		e.halt.cancel
		caret.erase

	def onbeforepaste e
		console.log 'onbeforepaste',e

	def onpaste e
		console.log 'onpaste',e
		var data = e.event:clipboardData
		var text = data.getData('text/plain')
		e.halt.cancel
		caret.insert(text)
		refocus
		repair
		# edit text: data

	def refresh
		# focusNode = sel.node # only if it is inside the scope?
		# caret.region = sel.region
		caret.render
		self

	def exec o
		var fn = o:command
		var args = o:args or []
		var ev = Imba.Event.new(type: 'command', target: dom, data: o)
		ev.data = o
		ev.process

		return

	def ontouchstart touch
		@rect = @body.dom.getBoundingClientRect

		return unless touch.button == 0

		if touch.@touch
			# is it not redirected?
			return touch.redirect({})

		var e = touch.event
		e.preventDefault
		# see if shift is down? should change behaviour
		var shift = e:shiftKey
		# log 'ontouchstart',touch,touch.x,touch.y,e,touch.button
		var [r,c] = rcForTouch(touch)

		if shift
			caret.selectable
		else
			caret.collapse

		caret.head.set(r,c).normalize
		caret.dirty
		# console.log 'touch start refocus?'
		refocus
		self

	def xyToRowCol x,y
		var col = Math.max(Math.round(x / charWidth),0)
		var row = Math.max(Math.ceil(y / lineHeight),1)
		return [row - 1,col]

	def rcForTouch touch
		var x = Math.max(touch.x - @rect:left,0)
		var y = Math.max(touch.y - @rect:top,0)
		return xyToRowCol(x,y)

	def ontouchupdate touch
		return unless touch.button == 0
		var [r,c] = rcForTouch(touch)
		caret.selectable
		caret.head.set(r,c).normalize
		caret.dirty
		self

	def ontouchend touch
		return unless touch.button == 0
		var [r,c] = rcForTouch(touch)
		caret.head.set(r,c).normalize
		caret.dirty 
		self

	def erase reg, edit
		reg = Region.normalize(reg,self)

		var text = reg.text
		history.onerase(reg,text,edit)

		var spans = nodesInRegion(reg,no,yes)
		# gropu the nodes
		observer.pause do
			if spans:length > 1
				spans[1]:node.setPrev(<iminsert.dirty>)

			elif spans[0] and spans[0]:mode == 'all'
				console.log 'removing single node?!'
				let before = spans[0]:node.prev

				spans[0]:node.setPrev(<iminsert.dirty>)

			for sel,i in spans
				# buffer need to updated during this?
				sel:node.erase(sel:region,sel:mode,edit)

		# delay('annotate',500) do annotate
		return erased(reg)

	def inserted loc, str
		console.log 'inserted',loc,str
		var reg = Region.new(loc,loc + str:length,null,self)
		for hint in hints
			hint.adjust(reg,yes)
		# hints.cleanup
		edited
		repair if util.isWhitespace(str)
		self

	def erased reg
		for hint in hints
			hint.adjust(reg,no)
		edited
		repair # repair synchronously

	def insert point, str, edit
		if point isa Region
			if point.size > 0
				logger.warn 'uncollapsed region in insert is not allowed'
			point = point.start

		log 'insert',point,str
		# should maybe create this as a command - and then make it happen?

		history.oninsert(point,str,edit)

		# log 'insert in view'
		var spans = nodesInRegion(Region.normalize(point,self),no)
		var mid = spans[0]
		var target = mid or spans:prev or spans:next
		var lft = spans:lft, rgt = spans:rgt
		var node
		var reg

		# log spans,mid,lft,rgt
		log 'before and after',lft,rgt,str

		if mid
			log 'insert mid',mid:node
			mid:node.insert(mid:region,str,edit,mid)

		else

			while rgt
				if rgt.canPrepend(str)
					log 'prepend',rgt,str
					rgt.insert('prepend',str,edit)
					return inserted(point,str)

				elif rgt.isFirst
					rgt = rgt.parent
					continue

				break

			# find the closest parent
			while lft
				if lft.canAppend(str)
					log 'append',lft,str
					lft.insert('append',str,edit)
					return inserted(point,str)

				elif lft.isLast
					lft = lft.parent
					continue
				
				break

			node = <iminsert>

			if lft
				lft.next = node
			elif rgt
				rgt.prev = node
			else
				# must be empty
				root.dom.appendChild(node.dom)
			
			node.insert('append',str,edit)

		return inserted(point,str)

	def onmutations
		self

	def repair
		@dirty = no
		var els = dom.getElementsByClassName('dirty')

		if els:length
			# logger.log "{els:length} dirty nodes to repair"

			var muts = for el in els
				tag(el)
			
			for mut in muts
				mut.unflag('dirty')
				mut.mutated(muts)
		self

	def code
		@root.dom:textContent

	def focusNodeDidSet new, old
		return unless root.contains(new)

		var path = []

		while new and new != root
			path.push(new)
			new = new.parent

		%(.focus_).map do |n|
			n.unflag('focus_') unless path.indexOf(n) >= 0

		for n,i in path
			n.flag('focus_')
		self


	def recompile
		# should happen in a separate thread - and be delayed
		console.log 'recompile'
		var res

		try
			res = Imbac.compile(code, bare: yes)

		if res
			compiled(res)
		self

	def reparse
		log 'reparse'
		root.rehighlight(inner: yes)
		return self

	def compiled res
		self

	def onrunerror e
		console.log 'onrunerror',e
		self

	def addError msg, loc
		var reg = Region.normalize(loc,self)
		console.log 'found warnings',reg,msg,loc
		if var node = nodeAtRegion(reg)
			log 'node at region is?!',node
			msg = msg.split(/error at (\[[\d\:]*\])\:\s*/).pop
			node.flag(:err)
			node.setAttribute('error',msg)
		delay('annotate',-1)
		self

	

	def annotate
		# console.log 'annotate'

		var state = root.codeState
		var code = state:code

		var apply = do |meta|
			var vars = []
			for scope in meta:scopes
				for v in scope:vars
					vars.push(v)

			var warnings = meta:warnings or []
			var oldWarnings = hints.filter do |hint| hint.group == 'analysis'

			if oldWarnings
				# could intelligently keep them instead
				hints.rem(oldWarnings)

			for warn in warnings
				warn:type ||= 'error'
				warn:group = 'analysis'
				hints.add(warn).activate

			return self if warnings:length

			var nodes = IM.textNodes(root.dom,yes)
			# what about removing old warnings?

			var map = {}
			for node,i in nodes
				map[node.@loc] = node

			# get textNodes with mapping(!)
			for variable,i in vars
				for ref,k in variable:refs
					var a = ref:loc[0]
					var b = ref:loc[1]
					var eref = "v{i}"

					if map[a]
						let dom = map[a]:parentNode
						let oldRef = dom.getAttribute('eref')
						# console.log 'setting the ref for node?',dom,dom.@tag
						tag(dom).eref = eref
						# if dom.@tag
						# 	dom.@tag.eref = eref
						# else
						# 	dom.setAttribute('eref',eref) unless oldRef == eref
						# 	dom:classList.add('lvar')

			return

		try
			
			console.time('analyze')
			IM.worker.analyze(code, bare: yes) do |res|
				console.log 'result from worker analyze'
				console.timeEnd('analyze')

				if res:data
					console.time('annotate')
					apply(res:data)
					console.timeEnd('annotate')
		catch e
			log 'error from annotate',e

		return self

	def oncommand e, c
		if self[c:command] isa Function
			self[c:command].call(self,c:args or [])
			e.halt
		self

	def dumpState o = {}
		{
			html: root.dom:innerHTML
			code: root.code
			selection: caret.region
			timestamp: Date.new
		}

	def loadState o = {}
		observer.pause do 
			if o:html
				root.dom:innerHTML = o:html
			elif o:code
				load(o:code)
			if o:selection
				caret.region = o:selection
		return self

	def loadSession session
		history.load(session)
		history.play
		self

	def textNodes rel = root
		IM.textNodes(rel)

	# Should be separate from the viewcode?
	def regionForNode node, rel = root
		var el = node.@dom or node
		var len = el:textContent:length
		var rng = document.createRange
		rng.setStart(rel.@dom or rel,0)
		rng.setEnd(node.@dom or node,0)
		var pre = rng.toString
		Region.new(pre:length,pre:length + len,rel,self)

	# Should merge with nodesInRegion
	def nodeAtRegion region, exact = no
		console.time('nodeAtRegion')
		var rel = root
		var a = region.a
		var b = region.b

		var nodes = textNodes(rel)
		# move into region instead?
		var pos = 0
		var match = null
		var adist,bdist,str,len

		for node,i in nodes
			# console.log 'looking through nodes'
			adist = a - pos
			bdist = b - pos
			str = node:textContent
			len = str:length
			
			if adist >= 0 and adist < len
				# console.log 'found starting point?',node,str,adist
				match = node
				break
				# return tag(node:parentNode)

			if bdist >= 0 and bdist < len
				# console.log 'found ending point',node,str,bdist
				# range.setEnd(node,bdist)
				break


			pos += len

		var el = tag(match:parentNode)
		# we want to match the one that is full length
		if exact and len < region.size
			while el
				# be careful
				var elreg = el.region
				return el if region.equals(elreg)
				el = el.parent

		console.timeEnd('nodeAtRegion')
		return match ? tag(match:parentNode) : null

	def nodesForEntity ref
		%([eref="{ref}"])

	# does not need to belong to view directly
	def nodesInRegion region, includeEnds = yes, generalize = no
		console.time('nodesInRegion')
		region = Region.normalize(region,self).normalize
		var a = region.start
		var b = region.end

		# can be optimized by supplying the regions
		var nodes = IM.textNodes(region.root or root)
		var matches = []
		var match
		var el
		# move into region instead?
		matches:includeEnds = includeEnds
		matches:region = region

		var pos = 0
		var ends = []

		for node,i in nodes
			# console.log 'looking through nodes'
			var adist = a - pos
			var bdist = b - pos
			var str = node:textContent
			var len = str:length

			if (pos + len) >= a and pos <= b
				el = tag(node:parentNode)
				var start = Math.max(0,a - pos)
				var end = Math.min(len, Math.max(b - pos,0))
				var par

				match = {
					node: el,
					startOffset: start,
					endOffset: end,
					region: Region.new(start,end,el,self),
					size: len
				}
				# log "node at {pos} + {len} - looking in range {a} - {b}"
				var mode = 'all'

				if start == len
					mode = 'end'
				elif end == 0
					mode = 'start'
				elif start == 0 and end == len
					var par = el.dom:parentNode
					var isOpener = par != @root.dom and el.dom == par:firstChild
					var isCloser = par != @root.dom and el.dom == par:lastChild

					if isOpener
						match:opens = el.parent
						ends.push(match)

					if isCloser
						var end = ends[ends:length - 1]
						if end and end:opens == el.parent
							end:closer = match
							match:opener = end
							ends.pop

						match:closes = el.parent

					mode = 'all'

				else
					mode = 'partial'
				
				match:mode = mode
				matches.push(match)

			pos += len
			break if pos > b

		var first = matches[0]
		var last = matches[matches:length - 1]

		if first and first:mode == 'end'
			matches:prev = first
			matches:lft = first:node

			# if first:node isa IM.Types:close
			# 	matches:lft = first:node.parent

			matches.shift unless includeEnds

		if last and last:mode == 'start'
			matches:next = last
			matches:rgt = last:node

			# if last:node isa IM.Types:open
			# 	matches:rgt = last:node.parent

			matches.pop unless includeEnds


		# normalize the nodes in groups
		if generalize
			# console.log 'generalize!',matches
			var i = 0
			var m
			while m = matches[i]
				if m:closer
					var idx = matches.indexOf(m:closer)
					var len = m:opens.size
					var new = {
						mode: 'all'
						region: Region.new(0,len,m:opens,self)
						startOffset: 0
						endOffset: len
						node: m:opens
					}
					var rem = matches.splice(i, idx - i + 1, new)
					new:children = rem
					# console.log 'slice away the items'
				i++

		console.timeEnd('nodesInRegion')
		return matches

	# should move to Buffer class
	def linecount
		buffer.linecount
		# buffer.split('\n')[:length]
	
	# Returns the contents of the region as a string.
	# Returns the character to the right of the point.
	def substr region, len
		buffer.substr(region,len)

	# move into Buffer
	def linestr nr
		buffer.line(nr)
		# if nr isa Number
		# 	buffer.split('\n')[nr] or ''

	def expandRegionTo region, match, forward = yes
		var buf = buffer.toString
		var pos = region.start
		var end = region.end

		if forward
			end++ while buf[end + 1] != match
		else
			pos-- while buf[pos - 1] != match
		
		Region.new(pos,end,self)
	

VIEW = null
