%%% @author  <marcin.miszczyk@erlang.solutions.com>
%%% @copyright (C) 2014
%%% @doc Mnesia backend for roster module
%%% @see mod_roster
%%%
%%% @end
%%% Created : 22 Jan 2014 by  <marcin.miszczyk@erlang.solutions.com

-module(mod_roster_odbc_back).
-author( 'marcin.miszczyk@erlang.solutions.com').


-behaviour( mod_roster_gen_backend ).
-export( [ init/1,
           roster_version/1,
           write_version/2,
           rosters_by_us/1,
           roster/1,
           write_roster/1,
           remove_roster/1,
           remove_roster_object/1,
           transaction/1,
           transaction/2
         ]).

-include("ejabberd.hrl").
-include("jlib.hrl").
-include("mod_roster.hrl").


%% --interface-----------------------------------------------------------



-spec init ( ModuleOptions ) -> ok when
      ModuleOptions :: list().
init( _Opts ) ->
    ok.


-spec roster_version( UserServer ) -> {ok, Version} | not_found when
      UserServer :: us(),
      Version :: version().
roster_version( US ) when size(US) =:= 2 ->
    {LUser, LServer} =  US,
    case odbc_queries:get_roster_version(ejabberd_odbc:escape(LServer),
                                         ejabberd_odbc:escape(LUser)) of
        {selected, ["version"], [{Version}]} ->
            {ok,Version};
        {selected, ["version"], []} ->
            not_found
    end.


-spec write_version( UserServer, RosterVersion ) -> any() when
      UserServer :: us(),
      RosterVersion :: version().
write_version( US, Version ) when size(US) =:= 2 ->
    {LUser, LServer} =  US,
    Transaction = fun () ->
                          odbc_queries:set_roster_version(ejabberd_odbc:escape(LUser), Version)
                  end,
    {atomic, {updated,1}} = odbc_queries:sql_transaction(LServer,
                                                         Transaction).


-spec rosters_by_us( UserServe ) -> Rosters when
      UserServe :: us(),
      Rosters :: list( roster() ).
rosters_by_us( US ) when size(US) =:= 2 ->
    {LUser, LServer} = US,
    Username = ejabberd_odbc:escape(LUser),
    case catch odbc_queries:get_roster(LServer, Username) of
        {selected, ["username", "jid", "nick", "subscription", "ask",
                    "askmessage", "server", "subscribe", "type"],
         Items} when is_list(Items) ->
            JIDGroups = case catch odbc_queries:get_roster_jid_groups(LServer, Username) of
                            {selected, ["jid","grp"], JGrps}
                              when is_list(JGrps) ->
                                JGrps;
                            _ ->
                                []
                        end,
            RItems = lists:flatmap(
                       fun(I) ->
                               case raw_to_record(LServer, I) of
                                   %% Bad JID in database:
                                   error ->
                                       [];
                                   R ->
                                       SJID = jlib:jid_to_binary(R#roster.jid),
                                       Groups = lists:flatmap(
                                                  fun({S, G}) when S == SJID ->
                                                          [G];
                                                     (_) ->
                                                          []
                                                  end, JIDGroups),
                                       [R#roster{groups = Groups}]
                               end
                       end, Items),
            RItems;
        _ ->
            []
    end.



-spec roster( UserServerJid ) -> MightBeRoster when
      UserServerJid :: usj(),
      MightBeRoster :: {ok, roster() } | not_found.
roster( USJ = {LUser, LServer, LJID} ) when size( USJ ) =:= 3 ->

    Username = ejabberd_odbc:escape(LUser),
    SJID = ejabberd_odbc:escape(jlib:jid_to_binary(LJID)),

    { selected,
      [ "username", "jid", "nick", "subscription",
        "ask", "askmessage", "server", "subscribe", "type"],
      Responce } = odbc_queries:get_roster_by_jid(LServer, Username, SJID),
    case Responce of
        [] ->
            _Return = not_found;
        [Item] ->
            Roster = raw_to_record( LServer, Item ),
            case Roster of
                error ->
                    _Return = not_found;
                _ ->
                    _Return = {ok, Roster}
            end
    end.


-spec remove_roster( UserServerJID ) -> ok when
      UserServerJID :: usj().
remove_roster( USJ = {LUser, LServer, LJID } ) when size(USJ) =:= 3 ->
    Username = ejabberd_odbc:escape(LUser),
    SJID = ejabberd_odbc:escape(jlib:jid_to_binary(LJID)),

    odbc_queries:del_roster(LServer, Username, SJID).



-spec remove_roster_object( Roster ) -> ok when
      Roster :: roster().
remove_roster_object( Roster = #roster{} ) ->
    not_implemented.


-spec write_roster( Roster ) -> ok when
      Roster :: roster().
write_roster( Roster = #roster{ usj = { LUser,
                                        LServer,
                                        LJID} } ) ->

    Username = ejabberd_odbc:escape(LUser),
    SJID = ejabberd_odbc:escape(jlib:jid_to_binary(LJID)),
    ItemVals = record_to_string( Roster ),
    ItemGroups = groups_to_string( Roster ),

    odbc_queries:update_roster(LServer,
                               Username,
                               SJID,
                               ItemVals,
                               ItemGroups).



-spec transaction( TransactionFun ) -> FunReturn when
      TransactionFun :: fun ( () -> FunReturn ).
transaction( Function ) ->
    not_implemented.


transaction( Host, Function ) ->
    odbc_queries:sql_transaction( Host, Function ).

%% --private-------------------------------------------------------------

raw_to_record(LServer, {User, BJID, Nick, BSubscription, BAsk, AskMessage,
                        _Server, _Subscribe, _Type}) ->
    case jlib:binary_to_jid(BJID) of
        error ->
            error;
        JID ->
            LJID = jlib:jid_tolower(JID),
            Subscription = case BSubscription of
                               <<"B">> -> both;
                               <<"T">> -> to;
                               <<"F">> -> from;
                               _ -> none
                           end,
            Ask = case BAsk of
                      <<"S">> -> subscribe;
                      <<"U">> -> unsubscribe;
                      <<"B">> -> both;
                      <<"O">> -> out;
                      <<"I">> -> in;
                      _ -> none
                  end,
            #roster{usj = {User, LServer, LJID},
                    us = {User, LServer},
                    jid = LJID,
                    name = Nick,
                    subscription = Subscription,
                    ask = Ask,
                    askmessage = AskMessage}
    end.


record_to_string(#roster{us = {User, _Server},
                         jid = JID,
                         name = Name,
                         subscription = Subscription,
                         ask = Ask,
                         askmessage = AskMessage}) ->
    Username = ejabberd_odbc:escape(User),
    SJID = ejabberd_odbc:escape(jlib:jid_to_binary(jlib:jid_tolower(JID))),
    Nick = ejabberd_odbc:escape(Name),
    SSubscription = case Subscription of
                        both -> "B";
                        to   -> "T";
                        from -> "F";
                        none -> "N"
                    end,
    SAsk = case Ask of
               subscribe   -> "S";
               unsubscribe -> "U";
               both        -> "B";
               out         -> "O";
               in          -> "I";
               none        -> "N"
           end,
    SAskMessage = ejabberd_odbc:escape(AskMessage),
    [Username, SJID, Nick, SSubscription, SAsk, SAskMessage, "N", "", "item"].

groups_to_string(#roster{us = {User, _Server},
                         jid = JID,
                         groups = Groups}) ->
    Username = ejabberd_odbc:escape(User),
    SJID = ejabberd_odbc:escape(jlib:jid_to_binary(jlib:jid_tolower(JID))),

    %% Empty groups do not need to be converted to string to be inserted in
    %% the database
    lists:foldl(
      fun([], Acc) -> Acc;
         (Group, Acc) ->
              G = ejabberd_odbc:escape(Group),
              [[Username, SJID, G]|Acc] end, [], Groups).
