%%--------------------------------------------------------------------
%% Copyright (c) 2022-2023 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------
-module(emqttb_behavior_pub).

-behavior(emqttb_worker).

%% API
-export([parse_metadata/1, my_autorate/1]).

%% behavior callbacks:
-export([init_per_group/2, init/1, handle_message/3, terminate/2]).

-export_type([prototype/0, config/0]).

-import(emqttb_worker, [send_after/2, send_after_rand/2, repeat/2,
                        my_group/0, my_id/0, my_clientid/0, my_cfg/1, connect/2]).

-include("../framework/emqttb_internal.hrl").

%%================================================================================
%% Type declarations
%%================================================================================

-type config() :: #{ topic          := binary()
                   , n_published    := lee:model_key()
                   , pubinterval    := lee:model_key()
                   , msg_size       := non_neg_integer()
                   , qos            := emqttb:qos()
                   , set_latency    := lee:key()
                   , retain         => boolean()
                   , metadata       => boolean()
                   , host_shift     => integer()
                   , host_selection => random | round_robin
                   }.

-type prototype() :: {?MODULE, config()}.

%%================================================================================
%% API
%%================================================================================

-spec parse_metadata(Msg) -> {ID, SeqNo, TS}
          when Msg :: binary(),
               ID :: integer(),
               SeqNo :: non_neg_integer(),
               TS :: integer().
parse_metadata(<<ID:32, SeqNo:32, TS:64, _/binary>>) ->
  {ID, SeqNo, TS}.

%%================================================================================
%% behavior callbacks
%%================================================================================

init_per_group(Group,
               #{ topic        := Topic
                , n_published  := NPublishedMetricKey
                , pubinterval  := PubInterval
                , msg_size     := MsgSize
                , qos          := QoS
                , set_latency  := SetLatencyKey
                } = Conf) when is_binary(Topic),
                               is_integer(MsgSize),
                               is_list(SetLatencyKey) ->
  AddMetadata = maps:get(metadata, Conf, false),
  PubCnt = emqttb_metrics:from_model(NPublishedMetricKey),
  emqttb_worker:new_opstat(Group, ?AVG_PUB_TIME),
  {auto, PubRate} = emqttb_autorate:from_model(PubInterval),
  MetadataSize = case AddMetadata of
                   true  -> (32 + 32 + 64) div 8;
                   false -> 0
                 end,
  HostShift = maps:get(host_shift, Conf, 0),
  HostSelection = maps:get(host_selection, Conf, random),
  Retain = maps:get(retain, Conf, false),
  #{ topic => Topic
   , message => message(max(0, MsgSize - MetadataSize))
   , pub_opts => [{qos, QoS}, {retain, Retain}]
   , pub_counter => PubCnt
   , pubinterval => PubRate
   , metadata => AddMetadata
   , host_shift => HostShift
   , host_selection => HostSelection
   }.

init(PubOpts = #{pubinterval := I}) ->
  rand:seed(default),
  {SleepTime, N} = emqttb:get_duration_and_repeats(I),
  send_after_rand(SleepTime, {publish, N}),
  HostShift = maps:get(host_shift, PubOpts, 0),
  HostSelection = maps:get(host_selection, PubOpts, random),
  {ok, Conn} = emqttb_worker:connect(#{ host_shift => HostShift
                                      , host_selection => HostSelection
                                      }),
  Conn.

handle_message(Shared, Conn, {publish, N1}) ->
  #{ topic := TP, pubinterval := I, message := Msg0, pub_opts := PubOpts
   , pub_counter := Cnt
   , metadata := AddMetadata
   } = Shared,
  {SleepTime, N2} = emqttb:get_duration_and_repeats(I),
  send_after(SleepTime, {publish, N2}),
  Msg = case AddMetadata of
          true  -> [message_metadata(), Msg0];
          false -> Msg0
        end,
  T = emqttb_worker:format_topic(TP),
  repeat(N1, fun() ->
                 emqttb_worker:call_with_counter(?AVG_PUB_TIME, emqtt, publish, [Conn, T, Msg, PubOpts]),
                 emqttb_metrics:counter_inc(Cnt, 1)
             end),
  {ok, Conn};
handle_message(_, Conn, _) ->
  {ok, Conn}.

terminate(_Shared, Conn) ->
  emqtt:disconnect(Conn).

%%================================================================================
%% Internal functions
%%================================================================================

my_autorate(Group) ->
  list_to_atom(atom_to_list(Group) ++ ".pub.rate").

message(Size) ->
  list_to_binary([$A || _ <- lists:seq(1, Size)]).

message_metadata() ->
  SeqNo = msg_seqno(),
  ID = erlang:phash2({node(), self()}),
  TS = os:system_time(microsecond),
  <<ID:32, SeqNo:32, TS:64>>.

msg_seqno() ->
  case get(emqttb_behavior_pub_seqno) of
    undefined -> N = 0;
    N         -> ok
  end,
  put(emqttb_behavior_pub_seqno, N + 1),
  N.
