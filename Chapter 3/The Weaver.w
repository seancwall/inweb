[Weaver::] The Weaver.

To weave a portion of the code into instructions for TeX.

@h The Master Weaver.
Here's what has happened so far, on a weave run of Inweb: on any other
sort of run, of course, we would never be in this section of code. The web was
read completely into memory and fully parsed. A request was then made either
to swarm a mass of individual weaves, or to make just a single weave, with the
target in each case being identified by its range. A further decoding layer
then translated each range into rather more basic details of what to weave and
where to put the result: and so we arrive at the front door of the routine
|Weaver::weave| below.

=
int Weaver::weave(weave_order *wv) {
	heterogeneous_tree *tree = WeaveTree::new_tree(wv);
	TEMPORARY_TEXT(banner)
	WRITE_TO(banner, "Weave of '%S' generated by Inweb", wv->booklet_title);
	tree_node *H = WeaveTree::head(tree, banner);
	DISCARD_TEXT(banner)
	tree_node *B = WeaveTree::body(tree);
	tree_node *T = WeaveTree::tail(tree, I"End of weave");
	Trees::make_child(H, tree->root);
	Trees::make_child(B, tree->root);
	Trees::make_child(T, tree->root);

	int lines = Weaver::weave_inner(wv, tree, B);

	WeaveTree::prune(tree);

	text_stream TO_struct;
	text_stream *OUT = &TO_struct;
	if (STREAM_OPEN_TO_FILE(OUT, wv->weave_to, UTF8_ENC) == FALSE)
		Errors::fatal_with_file("unable to write woven file", wv->weave_to);
	Formats::render(OUT, tree, wv->weave_to);
	STREAM_CLOSE(OUT);
	return lines;
}

@ =
int Weaver::weave_inner(weave_order *wv, heterogeneous_tree *tree, tree_node *body) {
	web *W = wv->weave_web;
	int lines_woven = 0;
	weaver_state state_at; weaver_state *state = &state_at;
	@<Start the weaver with a clean slate@>;
	chapter *C, *last_heading = NULL;
	section *S;
	LOOP_OVER_LINKED_LIST(C, chapter, W->chapters)
		if (C->md->imported == FALSE) {
			LOOP_OVER_LINKED_LIST(S, section, C->sections)
				if (Reader::range_within(S->md->sect_range, wv->weave_range)) {
					@<Weave any necessary chapter header@>;
					@<Weave any necessary section header@>;
					LanguageMethods::begin_weave(S, wv);
					@<Weave this section@>;
					@<Weave any necessary section footer@>;
				}
		}
	@<Weave any necessary chapter footer@>;
	return lines_woven;
}

@<Weave any necessary chapter header@> =
	if (last_heading != C) {
		@<Weave any necessary chapter footer@>;
		tree_node *CH = WeaveTree::chapter(tree, C);
		Trees::make_child(CH, state->body_node);
		state->chapter_node = CH;
		state->ap = CH;
		last_heading = C;
		if (wv->theme_match == NULL) {
			tree_node *H = WeaveTree::chapter_header(tree, C);
			Trees::make_child(H, state->chapter_node);
		}
	}

@<Weave any necessary chapter footer@> =
	if (wv->theme_match == NULL) {
		if (last_heading != NULL) {
			tree_node *F = WeaveTree::chapter_footer(tree, last_heading);
			Trees::make_child(F, state->chapter_node);
		}
	}

@<Weave any necessary section header@> =
	tree_node *SH = WeaveTree::section(tree, S);
	Trees::make_child(SH, state->chapter_node);
	state->section_node = SH;
	state->ap = SH;
	if (wv->theme_match == NULL) {
		tree_node *H = WeaveTree::section_header(tree, S);
		Trees::make_child(H, state->section_node);
	}

@<Weave any necessary section footer@> =
	if (wv->theme_match == NULL) {
		tree_node *F = WeaveTree::section_footer(tree, S);
		Trees::make_child(F, state->section_node);
	}

@h The state.
We can now begin on a clean page, by initialising the state of the weaver:

@e COMMENTARY_MATERIAL from 1
@e MACRO_MATERIAL          /* when a macro is being defined... */
@e DEFINITION_MATERIAL     /* ...versus when an |@d| definition is being made */
@e CODE_MATERIAL           /* verbatim code */
@e ENDNOTES_MATERIAL       /* endnotes at the foot of a paragraph */
@e FOOTNOTES_MATERIAL	   /* footnote texts for a paragraph */

=
typedef struct weaver_state {
	int kind_of_material; /* one of the enumerated |*_MATERIAL| constants above */
	int line_break_pending; /* insert a line break before the next woven line? */
	int next_heading_without_vertical_skip;
	int horizontal_rule_just_drawn;
	struct section *last_extract_from;
	struct tree_node *body_node;
	struct tree_node *chapter_node;
	struct tree_node *section_node;
	struct tree_node *para_node;
	struct tree_node *carousel_node;
	struct tree_node *material_node;
	struct tree_node *ap;
} weaver_state;

@<Start the weaver with a clean slate@> =
	state->kind_of_material = COMMENTARY_MATERIAL;
	state->line_break_pending = FALSE;
	state->next_heading_without_vertical_skip = FALSE;
	state->horizontal_rule_just_drawn = FALSE;
	state->last_extract_from = NULL;
	state->body_node = body;
	state->chapter_node = NULL;
	state->section_node = NULL;
	state->para_node = NULL;
	state->carousel_node = NULL;
	state->material_node = NULL;
	state->ap = body;

@h Weaving a section.

@<Weave this section@> =
	paragraph *current_P = NULL;
	int toc_made = FALSE;
	for (source_line *LLL = S->first_line; LLL; LLL = LLL->next_line) {
		wv->current_weave_line = LLL;
		if (LLL->owning_paragraph == NULL)
			@<Largely ignore this extra-mural line@>
		else if (LLL->owning_paragraph != current_P) {
			if (toc_made == FALSE) {
				if (Str::len(S->sect_purpose) > 0) {
					tree_node *F = WeaveTree::purpose(tree, S->sect_purpose);
					Trees::make_child(F, state->ap);
				}
				Weaver::weave_table_of_contents(tree, state->ap, S);
				toc_made = TRUE;
			}
			current_P = LLL->owning_paragraph;
			if (Tags::tagged_with(current_P, wv->theme_match))
				@<Weave this paragraph@>;
		}
	}

@<Largely ignore this extra-mural line@> =
	if (LLL->category == INTERFACE_BODY_LCAT) {
		state->horizontal_rule_just_drawn = FALSE;
		continue;
	}
	if (LLL->category == PURPOSE_BODY_LCAT)  {
		continue;
	}
	if (LLL->category == DEFINITIONS_LCAT) {
		Weaver::weave_subheading(tree, wv, state->ap, I"Definitions");
		state->next_heading_without_vertical_skip = TRUE;
		state->horizontal_rule_just_drawn = FALSE;
		continue;
	}
	if (LLL->category == BAR_LCAT) {
		state->kind_of_material = COMMENTARY_MATERIAL;
		state->next_heading_without_vertical_skip = TRUE;
		if (state->horizontal_rule_just_drawn == FALSE) {
			tree_node *B = WeaveTree::bar(tree);
			Trees::make_child(B, state->ap);
		}
		continue;
	}
	if ((LLL->category == CHAPTER_HEADING_LCAT) ||
		(LLL->category == SECTION_HEADING_LCAT))
		continue;

@<Weave this paragraph@> =
	if (current_P->starts_on_new_page)
		Trees::make_child(WeaveTree::pagebreak(tree), state->ap);
	source_line *L = LLL;
	if ((L->category != HEADING_START_LCAT) &&
		(L->category != PARAGRAPH_START_LCAT))
		Main::error_in_web(I"bad start to paragraph", L); /* should never happen */

	@<Deal with the marker for the start of a new paragraph, section or chapter@>;

	@<Weave any regular commentary text after the heading on the same line@>;
	L = L->next_line;
	for (; ((L) && (L->owning_paragraph == current_P)); L = L->next_line) {
		wv->current_weave_line = L;
		if (LanguageMethods::skip_in_weaving(S->sect_language, wv, L) == FALSE) {
			lines_woven++;
			@<Respond to any commands aimed at the weaver, and otherwise skip commands@>;
			@<Weave this line@>;
		}
	}
	L = NULL;
	Weaver::change_material(tree, state, ENDNOTES_MATERIAL, FALSE, NULL);
	Weaver::show_endnotes_on_previous_paragraph(tree, wv, state->ap, current_P);

@h How paragraphs begin.

@<Deal with the marker for the start of a new paragraph, section or chapter@> =
	LanguageMethods::reset_syntax_colouring(S->sect_language);
	if (wv->theme_match) @<Apply special rules for thematic extracts@>;
	state->para_node = WeaveTree::paragraph_heading(tree, current_P,
		state->next_heading_without_vertical_skip);
	Trees::make_child(state->para_node, state->section_node);
	Weaver::change_material_for_para(tree, state);
	state->kind_of_material = COMMENTARY_MATERIAL;
	state->next_heading_without_vertical_skip = FALSE;

@ If we are weaving a selection of extracted paragraphs, normal conventions
about breaking pages at chapters and sections fail to work. So:

@<Apply special rules for thematic extracts@> =
	text_stream *cap = Tags::retrieve_caption(L->owning_paragraph, wv->theme_match);
	if (Str::len(cap) > 0) {
		Weaver::weave_subheading(tree, wv, state->ap, C->md->ch_title);
	} else if (state->last_extract_from != S) {
		TEMPORARY_TEXT(extr)
		WRITE_TO(extr, "From %S: %S", C->md->ch_title, S->md->sect_title);
		Weaver::weave_subheading(tree, wv, state->ap, extr);
		DISCARD_TEXT(extr)
	}
	state->last_extract_from = S;

@ There's quite likely ordinary text on the line following the paragraph
 start indication, too, so we need to weave this out:

@<Weave any regular commentary text after the heading on the same line@> =
	if (Str::len(L->text_operand2) > 0) {
		TEMPORARY_TEXT(matter)
		WRITE_TO(matter, "%S\n", L->text_operand2);
		Weaver::commentary_text(tree, wv, state->ap, matter);
		DISCARD_TEXT(matter)
	}

@<Weave this line@> =
	if (L->category == BEGIN_CODE_LCAT) {
		state->line_break_pending = FALSE;
		LanguageMethods::reset_syntax_colouring(S->sect_language);
		continue;
	}

	if (L->category == END_EXTRACT_LCAT) {
		Weaver::change_material(tree, state, COMMENTARY_MATERIAL, FALSE, NULL);
		continue;
	}

	TEMPORARY_TEXT(matter) Str::copy(matter, L->text);
	if (L->is_commentary) @<Weave verbatim matter in commentary style@>
	else @<Weave verbatim matter in code style@>;
	DISCARD_TEXT(matter)

@ And lastly we ignore commands, or act on them if they happen to be aimed
at us; but we don't weave them into the output, that's for sure.

@<Respond to any commands aimed at the weaver, and otherwise skip commands@> =
	if (L->category == COMMAND_LCAT) {
		if (L->command_code == PAGEBREAK_CMD)
			Trees::make_child(WeaveTree::pagebreak(tree), state->ap);
		if (L->command_code == GRAMMAR_INDEX_CMD)
			Trees::make_child(WeaveTree::grammar_index(tree), state->ap);
		if (L->command_code == FIGURE_CMD) @<Weave a figure@>;
		if (L->command_code == AUDIO_CMD) @<Weave an audio clip@>;
		if (L->command_code == VIDEO_CMD) @<Weave a video clip@>;
		if (L->command_code == DOWNLOAD_CMD) @<Weave a download@>;
		if (L->command_code == EMBED_CMD) @<Weave an embed@>;
		if (L->command_code == CAROUSEL_CMD) @<Weave a carousel@>;
		if (L->command_code == CAROUSEL_ABOVE_CMD) @<Weave a carousel@>;
		if (L->command_code == CAROUSEL_BELOW_CMD) @<Weave a carousel@>;
		if (L->command_code == CAROUSEL_UNCAPTIONED_CMD) @<Weave a carousel@>;
		if (L->command_code == CAROUSEL_END_CMD) @<Weave a carousel end@>;
		/* Otherwise assume it was a tangler command, and ignore it here */
		continue;
	}

@<Weave a figure@> =
	int w, h;
	text_stream *figname = Parser::dimensions(L->text_operand, &w, &h, L);
	Trees::make_child(WeaveTree::figure(tree, figname, w, h), state->ap);

@<Weave an audio clip@> =
	int w, h;
	text_stream *figname = Parser::dimensions(L->text_operand, &w, &h, L);
	Trees::make_child(WeaveTree::audio(tree, figname, w), state->ap);

@<Weave a video clip@> =
	int w, h;
	text_stream *figname = Parser::dimensions(L->text_operand, &w, &h, L);
	Trees::make_child(WeaveTree::video(tree, figname, w, h), state->ap);

@<Weave a download@> =
	Trees::make_child(WeaveTree::download(tree, L->text_operand, L->text_operand2),
		state->ap);

@<Weave an embed@> =
	int w, h;
	text_stream *ID = Parser::dimensions(L->text_operand2, &w, &h, L);
	Trees::make_child(WeaveTree::embed(tree, L->text_operand, ID, w, h), state->ap);

@<Weave a carousel@> =
	tree_node *C = WeaveTree::carousel_slide(tree, L->text_operand, L->command_code);
	Trees::make_child(C, state->para_node);
	state->ap = C;
	state->carousel_node = C;

@<Weave a carousel end@> =
	state->ap = state->para_node;
	state->carousel_node = NULL;

@h Commentary matter.
Typographically this is a fairly simple business: it's almost the case that
we only have to transcribe it. But not quite!

@<Weave verbatim matter in commentary style@> =
	@<Weave displayed source in its own special style@>;
	@<Weave a blank line as a thin vertical skip and paragraph break@>;
	@<Weave bracketed list indications at start of line into items@>;
	@<Weave tabbed code material as a new indented paragraph@>;
	@<Weave footnotes@>;
	WRITE_TO(matter, "\n");
	Weaver::commentary_text(tree, wv, state->ap, matter);
	continue;

@ Displayed source is the material marked with |>>| arrows in column 1.

@<Weave displayed source in its own special style@> =
	if (L->category == SOURCE_DISPLAY_LCAT) {
		Trees::make_child(WeaveTree::display_line(tree, L->text_operand), state->ap);
		continue;
	}

@ Our style is to use paragraphs without initial-line indentation, so we
add a vertical skip between them to show the division more clearly.

@<Weave a blank line as a thin vertical skip and paragraph break@> =
	if (Regexp::string_is_white_space(matter)) {
		if ((L->next_line) && (L->next_line->category == COMMENT_BODY_LCAT)) {
			match_results mr = Regexp::create_mr();
			if ((state->kind_of_material != CODE_MATERIAL) ||
				(Regexp::match(&mr, matter, L"\t|(%c*)|(%c*?)")))
				Trees::make_child(WeaveTree::vskip(tree, TRUE), state->ap);
			Regexp::dispose_of(&mr);	
		}
		continue;
	}

@ Here our extension is simply to provide a tidier way to use TeX's standard
|\item| and |\itemitem| macros for indented list items.

@<Weave bracketed list indications at start of line into items@> =
	match_results mr = Regexp::create_mr();
	if (Regexp::match(&mr, matter, L"%(-...%) (%c*)")) { /* continue double */
		Weaver::change_material(tree, state, COMMENTARY_MATERIAL, FALSE, NULL);
		Trees::make_child(WeaveTree::weave_item_node(tree, 2, I""), state->ap);
		Str::copy(matter, mr.exp[0]);
	} else if (Regexp::match(&mr, matter, L"%(...%) (%c*)")) { /* continue single */
		Weaver::change_material(tree, state, COMMENTARY_MATERIAL, FALSE, NULL);
		Trees::make_child(WeaveTree::weave_item_node(tree, 1, I""), state->ap);
		Str::copy(matter, mr.exp[0]);
	} else if (Regexp::match(&mr, matter, L"%(-([a-zA-Z0-9*]+)%) (%c*)")) { /* begin double */
		Weaver::change_material(tree, state, COMMENTARY_MATERIAL, FALSE, NULL);
		Trees::make_child(WeaveTree::weave_item_node(tree, 2, mr.exp[0]), state->ap);
		Str::copy(matter, mr.exp[1]);
	} else if (Regexp::match(&mr, matter, L"%(([a-zA-Z0-9*]+)%) (%c*)")) { /* begin single */
		Weaver::change_material(tree, state, COMMENTARY_MATERIAL, FALSE, NULL);
		Trees::make_child(WeaveTree::weave_item_node(tree, 1, mr.exp[0]), state->ap);
		Str::copy(matter, mr.exp[1]);
	}
	Regexp::dispose_of(&mr);

@ Finally, matter encased in vertical strokes one tab stop in from column 1
in the source is set indented in code style.

@<Weave tabbed code material as a new indented paragraph@> =
	match_results mr = Regexp::create_mr();
	if (Regexp::match(&mr, matter, L"\t|(%c*)|(%c*?)")) {
		TEMPORARY_TEXT(original)
		Weaver::change_material(tree, state, CODE_MATERIAL, FALSE, NULL);
 		Str::copy(original, mr.exp[0]);
		Str::copy(matter, mr.exp[1]);
		TEMPORARY_TEXT(colouring)
		for (int i=0; i<Str::len(original); i++) PUT_TO(colouring, PLAIN_COLOUR);
		tree_node *CL = WeaveTree::code_line(tree);
		Trees::make_child(CL, state->ap);
		TextWeaver::source_code(tree, CL, original, colouring, L->enable_hyperlinks);
		DISCARD_TEXT(colouring)
		DISCARD_TEXT(original)
		Weaver::commentary_text(tree, wv, state->ap, matter);
		Regexp::dispose_of(&mr);
		continue;
	}
	Regexp::dispose_of(&mr);

@<Weave footnotes@> =
	if (L->category == FOOTNOTE_TEXT_LCAT) {
		Weaver::change_material(tree, state, FOOTNOTES_MATERIAL, FALSE, NULL);
		footnote *F = L->footnote_text;
		tree_node *FN = WeaveTree::footnote(tree, F->cue_text);
		Trees::make_child(FN, state->material_node);
		if (F->cued_already == FALSE) Main::error_in_web(I"footnote never cued", L);
		state->ap = FN;
	}

@h Code-like matter.
Even though Inweb's approach, unlike |CWEB|'s, is to respect the layout
of the original, this is still quite typographically complex: commentary
and macro usage is rendered differently.

@<Weave verbatim matter in code style@> =
	@<Change material if necessary@>;
	@<Weave a blank line as a thin vertical skip@>;

	Str::rectify_indentation(matter, 4);

	TEMPORARY_TEXT(prefatory)
	TEMPORARY_TEXT(concluding_comment)
	@<Extract any comment matter ending the line to be set in italic@>;
	@<Give constant definition lines slightly fancier openings@>;

	tree_node *CL = WeaveTree::code_line(tree);
	Trees::make_child(CL, state->ap);
	if (Str::len(prefatory) > 0)
		Trees::make_child(WeaveTree::weave_defn_node(tree, prefatory), CL);
	Str::clear(prefatory);

	@<Offer the line to the language to weave@>;

	@<Find macro usages and adjust syntax colouring accordingly@>;
	TEMPORARY_TEXT(colouring)
	LanguageMethods::syntax_colour(S->sect_language, wv, L, matter, colouring);
	TextWeaver::source_code(tree, CL, matter, colouring, L->enable_hyperlinks);
	DISCARD_TEXT(colouring)

	if (Str::len(concluding_comment) > 0)
		TextWeaver::comment_text_in_code(tree, CL, concluding_comment);
	DISCARD_TEXT(concluding_comment)
	DISCARD_TEXT(prefatory)
	
	ClumsyLabel: ;

@ We're not in Kansas any more, so:

@<Change material if necessary@> =
	if (state->kind_of_material != CODE_MATERIAL) {
		int will_be = CODE_MATERIAL;
		if (L->category == MACRO_DEFINITION_LCAT)
			will_be = MACRO_MATERIAL;
		else if ((L->category == BEGIN_DEFINITION_LCAT) ||
				(L->category == CONT_DEFINITION_LCAT))
			will_be = DEFINITION_MATERIAL;
		else if ((state->kind_of_material == DEFINITION_MATERIAL) &&
			((L->category == CODE_BODY_LCAT) || (L->category == COMMENT_BODY_LCAT)) &&
			(Str::len(L->text) == 0))
			will_be = DEFINITION_MATERIAL;
		programming_language *pl = L->colour_as;
		if (pl == NULL) pl = S->sect_language;
		if (will_be != CODE_MATERIAL) pl = NULL;
		theme_tag *T = Tags::find_by_name(I"Preform", FALSE);
		if ((T) && (Tags::tagged_with(L->owning_paragraph, T))) {
			programming_language *prepl =
				Languages::find_by_name(I"Preform", wv->weave_web, FALSE);
			if (prepl) pl = prepl;
		}
		Weaver::change_material(tree, state, will_be, L->plainer, pl);
		state->line_break_pending = FALSE;
	}

@ A blank line is implemented differently in different formats, so it gets
a node of its own, a vskip:

@<Weave a blank line as a thin vertical skip@> =
	if (state->line_break_pending) {
		Trees::make_child(WeaveTree::vskip(tree, FALSE), state->ap);
		state->line_break_pending = FALSE;
	}
	if (Regexp::string_is_white_space(matter)) {
		state->line_break_pending = TRUE;
		goto ClumsyLabel;
	}

@ Comments which run to the end of a line can be set in italic type, for
example, or flush left.

@<Extract any comment matter ending the line to be set in italic@> =
	TEMPORARY_TEXT(part_before_comment)
	TEMPORARY_TEXT(part_within_comment)
	programming_language *pl = S->sect_language;
	if (L->category == TEXT_EXTRACT_LCAT) pl = L->colour_as;
	if ((pl) && (LanguageMethods::parse_comment(pl,
		matter, part_before_comment, part_within_comment))) {
		Str::copy(matter, part_before_comment);
		Str::copy(concluding_comment, part_within_comment);
	}
	DISCARD_TEXT(part_before_comment)
	DISCARD_TEXT(part_within_comment)

@ Set the |@d| definition escape very slightly more fancily:

@<Give constant definition lines slightly fancier openings@> =
	if (L->category == BEGIN_DEFINITION_LCAT) {
		match_results mr = Regexp::create_mr();
		if ((Regexp::match(&mr, matter, L"@d (%c*)")) ||
			(Regexp::match(&mr, matter, L"@define (%c*)"))) {
			Str::copy(prefatory, I"define");
			Str::copy(matter, mr.exp[0]);
		} else if (Regexp::match(&mr, matter, L"@default (%c*)")) {
			Str::copy(prefatory, I"default");
			Str::copy(matter, mr.exp[0]);
		} else if ((Regexp::match(&mr, matter, L"@e (%c*)")) ||
			(Regexp::match(&mr, matter, L"@enum (%c*)"))) {
			Str::copy(prefatory, I"enum");
			Str::copy(matter, mr.exp[0]);
		}
		Regexp::dispose_of(&mr);
	}

@<Offer the line to the language to weave@> =
	TEMPORARY_TEXT(OUT)
	int taken = LanguageMethods::weave_code_line(OUT, S->sect_language, wv,
		W, C, S, L, matter, concluding_comment);
	if (taken) {
		tree_node *V = WeaveTree::verbatim(tree, OUT);
		Trees::make_child(V, CL);
	}
	DISCARD_TEXT(OUT)
	if (taken) goto ClumsyLabel;

@<Find macro usages and adjust syntax colouring accordingly@> =
	match_results mr = Regexp::create_mr();
	while (Regexp::match(&mr, matter, L"(%c*?)%@%<(%c*?)%@%>(%c*)")) {
		para_macro *pmac = Macros::find_by_name(mr.exp[1], S);
		if (pmac) {
			TEMPORARY_TEXT(front_colouring)
			LanguageMethods::syntax_colour(S->sect_language, wv, L, mr.exp[0], front_colouring);
			TextWeaver::source_code(tree, CL, mr.exp[0], front_colouring, L->enable_hyperlinks);
			DISCARD_TEXT(front_colouring)
			Str::copy(matter, mr.exp[2]);
			int defn = (L->owning_paragraph == pmac->defining_paragraph)?TRUE:FALSE;
			if (defn) Str::clear(matter);
			Trees::make_child(WeaveTree::pmac(tree, pmac, defn), CL);
		} else break;
	}
	Regexp::dispose_of(&mr);

@h Endnotes.
The endnotes describe function calls from far away, or unexpected
structure usage, or how |CWEB|-style code substitutions were made.

=
void Weaver::show_endnotes_on_previous_paragraph(heterogeneous_tree *tree,
	weave_order *wv, tree_node *ap, paragraph *P) {
	tree_node *body = ap;
	theme_tag *T = Tags::find_by_name(I"Preform", FALSE);
	if ((T) && (Tags::tagged_with(P, T)))
		@<Show endnote on use of Preform@>;
	Tags::show_endnote_on_ifdefs(tree, ap, P);
	if (P->defines_macro)
		@<Show endnote on where paragraph macro is used@>;
	language_function *fn;
	LOOP_OVER_LINKED_LIST(fn, language_function, P->functions)
		@<Show endnote on where this function is used@>;
	language_type *st;
	LOOP_OVER_LINKED_LIST(st, language_type, P->structures)
		@<Show endnote on where this language type is accessed@>;
}

@<Show endnote on use of Preform@> =
	tree_node *E = WeaveTree::endnote(tree);
	Trees::make_child(E, body); ap = E;
	TextWeaver::commentary_text(tree, ap, I"This is ");
	TEMPORARY_TEXT(url)
	int ext = FALSE;
	if (Colonies::resolve_reference_in_weave(url, NULL, wv->weave_to,
		I"words: About Preform", wv->weave_web->md, NULL, &ext))
		Trees::make_child(WeaveTree::url(tree, url, I"Preform grammar", ext), ap);
	else
		TextWeaver::commentary_text(tree, ap, I"Preform grammar");
	DISCARD_TEXT(url)
	TextWeaver::commentary_text(tree, ap, I", not regular C code.");	

@<Show endnote on where paragraph macro is used@> =
	tree_node *E = WeaveTree::endnote(tree);
	Trees::make_child(E, body); ap = E;
	TextWeaver::commentary_text(tree, ap, I"This code is ");
	int ct = 0;
	macro_usage *mu;
	LOOP_OVER_LINKED_LIST(mu, macro_usage, P->defines_macro->macro_usages)
		ct++;
	if (ct == 1) TextWeaver::commentary_text(tree, ap, I"never used");
	else {
		int k = 0, used_flag = FALSE;
		LOOP_OVER_LINKED_LIST(mu, macro_usage, P->defines_macro->macro_usages)
			if (P != mu->used_in_paragraph) {
				if (used_flag) {
					if (k < ct-1) TextWeaver::commentary_text(tree, ap, I", ");
					else TextWeaver::commentary_text(tree, ap, I" and ");
				} else {
					TextWeaver::commentary_text(tree, ap, I"used in ");
				}
				Trees::make_child(WeaveTree::locale(tree, mu->used_in_paragraph, NULL), ap);
				used_flag = TRUE; k++;
				switch (mu->multiplicity) {
					case 1: break;
					case 2: TextWeaver::commentary_text(tree, ap, I" (twice)"); break;
					case 3: TextWeaver::commentary_text(tree, ap, I" (three times)"); break;
					case 4: TextWeaver::commentary_text(tree, ap, I" (four times)"); break;
					case 5: TextWeaver::commentary_text(tree, ap, I" (five times)"); break;
					default: {
						TEMPORARY_TEXT(mt)
						WRITE_TO(mt, " (%d times)", mu->multiplicity);
						TextWeaver::commentary_text(tree, ap, mt);
						DISCARD_TEXT(mt)
						break;
					}
				}
			}
	}
	TextWeaver::commentary_text(tree, ap, I".");

@<Show endnote on where this function is used@> =
	if (fn->usage_described == FALSE)
		Weaver::show_function_usage(tree, wv, ap, P, fn, FALSE);

@<Show endnote on where this language type is accessed@> =
	tree_node *E = WeaveTree::endnote(tree);
	Trees::make_child(E, body); ap = E;
	TextWeaver::commentary_text(tree, ap, I"The structure ");
	TextWeaver::commentary_text(tree, ap, st->structure_name);

	section *S;
	LOOP_OVER(S, section) S->scratch_flag = FALSE;
	structure_element *elt;
	LOOP_OVER_LINKED_LIST(elt, structure_element, st->elements) {
		hash_table_entry *hte =
			Analyser::find_hash_entry_for_section(elt->element_created_at->owning_section,
				elt->element_name, FALSE);
		if (hte) {
			hash_table_entry_usage *hteu;
			LOOP_OVER_LINKED_LIST(hteu, hash_table_entry_usage, hte->usages)
				if (hteu->form_of_usage & ELEMENT_ACCESS_USAGE)
					hteu->usage_recorded_at->under_section->scratch_flag = TRUE;
		}
	}

	int usage_count = 0, external = 0;
	LOOP_OVER(S, section)
		if (S->scratch_flag) {
			usage_count++;
			if (S != P->under_section) external++;
		}
	if (external == 0) TextWeaver::commentary_text(tree, ap, I" is private to this section");
	else {
		TextWeaver::commentary_text(tree, ap, I" is accessed in ");
		int c = 0;
		LOOP_OVER(S, section)
			if ((S->scratch_flag) && (S != P->under_section)) {
				if (c++ > 0) TextWeaver::commentary_text(tree, ap, I", ");
				TextWeaver::commentary_text(tree, ap, S->md->sect_range);
			}
		if (P->under_section->scratch_flag) TextWeaver::commentary_text(tree, ap, I" and here");
	}
	TextWeaver::commentary_text(tree, ap, I".");

@ =
void Weaver::show_function_usage(heterogeneous_tree *tree, weave_order *wv,
	tree_node *ap, paragraph *P, language_function *fn, int as_list) {
	tree_node *body = ap;
	fn->usage_described = TRUE;
	hash_table_entry *hte =
		Analyser::find_hash_entry_for_section(fn->function_header_at->owning_section,
			fn->function_name, FALSE);
	if (as_list == FALSE) {
		tree_node *E = WeaveTree::endnote(tree);
		Trees::make_child(E, body); ap = E;
		TextWeaver::commentary_text(tree, ap, I"The function ");
		TextWeaver::commentary_text(tree, ap, fn->function_name);
	}
	int used_flag = FALSE;
	hash_table_entry_usage *hteu = NULL;
	section *last_cited_in = NULL;
	int count_under = 0;
	LOOP_OVER_LINKED_LIST(hteu, hash_table_entry_usage, hte->usages)
		if ((P != hteu->usage_recorded_at) &&
			(P->under_section == hteu->usage_recorded_at->under_section))
			@<Cite usage of function here@>;
	LOOP_OVER_LINKED_LIST(hteu, hash_table_entry_usage, hte->usages)
		if (P->under_section != hteu->usage_recorded_at->under_section)
			@<Cite usage of function here@>;
	if (used_flag == FALSE) {
		if (as_list == FALSE) {
			TextWeaver::commentary_text(tree, ap, I" appears nowhere else");
		} else {
			TextWeaver::commentary_text(tree, ap, I"none");
		}
	}
	if (as_list == FALSE) {
		if ((last_cited_in != P->under_section) && (last_cited_in))
			TextWeaver::commentary_text(tree, ap, I")");
		TextWeaver::commentary_text(tree, ap, I".");
	}
}

@<Cite usage of function here@> =
	if (as_list == FALSE) {
		if (used_flag == FALSE) TextWeaver::commentary_text(tree, ap, I" is used in ");
	}
	used_flag = TRUE;
	section *S = hteu->usage_recorded_at->under_section;
	if ((S != last_cited_in) && (S != P->under_section)) {
		count_under = 0;
		if (last_cited_in) {
			if (as_list == FALSE) {
				if (last_cited_in != P->under_section) TextWeaver::commentary_text(tree, ap, I"), ");
				else TextWeaver::commentary_text(tree, ap, I", ");
			} else {
				Trees::make_child(WeaveTree::linebreak(tree), ap);
			}
		}
		TextWeaver::commentary_text(tree, ap, hteu->usage_recorded_at->under_section->md->sect_title);
		if (as_list == FALSE) TextWeaver::commentary_text(tree, ap, I" (");
		else TextWeaver::commentary_text(tree, ap, I" - ");
	}
	if (count_under++ > 0) TextWeaver::commentary_text(tree, ap, I", ");
	Trees::make_child(WeaveTree::locale(tree, hteu->usage_recorded_at, NULL), ap);
	last_cited_in = hteu->usage_recorded_at->under_section;

@h Non-paragraph subheadings.

=
void Weaver::weave_subheading(heterogeneous_tree *tree, weave_order *wv,
	tree_node *ap, text_stream *text) {
	tree_node *D = WeaveTree::subheading(tree, text);
	Trees::make_child(D, ap);
}

void Weaver::change_material(heterogeneous_tree *tree,
	weaver_state *state, int new_material, int plainly, programming_language *pl) {
	if (state->kind_of_material != new_material) {
		tree_node *D = WeaveTree::material(tree, new_material, plainly, pl);
		if (state->carousel_node) Trees::make_child(D, state->carousel_node);
		else Trees::make_child(D, state->para_node);
		state->material_node = D;
		state->ap = D;
		state->kind_of_material = new_material;
	}
}

void Weaver::change_material_for_para(heterogeneous_tree *tree, weaver_state *state) {
	tree_node *D = WeaveTree::material(tree, COMMENTARY_MATERIAL, FALSE, NULL);
	Trees::make_child(D, state->para_node);
	state->material_node = D;
	state->ap = D;
	state->kind_of_material = COMMENTARY_MATERIAL;
}

void Weaver::figure(heterogeneous_tree *tree, weave_order *wv,
	tree_node *ap, text_stream *figname, int w, int h) {
	tree_node *F = WeaveTree::figure(tree, figname, w, h);
	Trees::make_child(F, ap);
}

void Weaver::commentary_text(heterogeneous_tree *tree, weave_order *wv,
	tree_node *ap, text_stream *matter) {
	TextWeaver::commentary_text(tree, ap, matter);
}

@h Section tables of contents.
These appear at the top of each woven section, and give links to the paragraphs
marked as |@h| headings.

=
int Weaver::weave_table_of_contents(heterogeneous_tree *tree,
	tree_node *ap, section *S) {
	int noteworthy = 0;
	paragraph *P;
	LOOP_OVER_LINKED_LIST(P, paragraph, S->paragraphs)
		if ((P->weight > 0) && ((S->barred == FALSE) || (P->above_bar == FALSE)))
			noteworthy++;
	if (noteworthy == 0) return FALSE;

	tree_node *TOC = WeaveTree::table_of_contents(tree, S->md->sect_range);
	Trees::make_child(TOC, ap);
	LOOP_OVER_LINKED_LIST(P, paragraph, S->paragraphs)
		if ((P->weight > 0) && ((S->barred == FALSE) || (P->above_bar == FALSE))) {
			TEMPORARY_TEXT(loc)
			WRITE_TO(loc, "%S%S", P->ornament, P->paragraph_number);
			Trees::make_child(
				WeaveTree::contents_line(tree, loc,
					P->first_line_in_paragraph->text_operand, P), TOC);
			DISCARD_TEXT(loc)
		}
	return TRUE;
}

