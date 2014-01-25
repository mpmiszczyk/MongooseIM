%%% @author marcin piotr miszczyk  <marcin.miszczyk@erlang.solutions.com>
%%% @copyright (C) 2014
%%% @doc Bahaviour definition for mod_roster backends
%%% @see mod_roster_mnesia
%%% @see mod_roster_odbc
%%%
%%% @end
%%% Created : 22 Jan 2014 by  <marcin.miszczyk@erlang.solutions.com>

-module(mod_roster_gen_backend).
-author( 'marcin.miszczyk@erlang.solutions.com').

-callback init( Options ) -> ok when
      Options :: list().

