%%--------------------------------------------------------------------
%% Copyright (c) 2022-2024 EMQ Technologies Co., Ltd. All Rights Reserved.
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
-ifndef(EMQX_TRACE_HRL).
-define(EMQX_TRACE_HRL, true).

-define(TRACE, emqx_trace).

-record(?TRACE, {
    name :: binary() | undefined | '_',
    type :: clientid | topic | ip_address | undefined | '_',
    filter ::
        emqx_types:topic() | emqx_types:clientid() | emqx_trace:ip_address() | undefined | '_',
    enable = true :: boolean() | '_',
    payload_encode = text :: hex | text | hidden | '_',
    extra = #{} :: map() | '_',
    start_at :: integer() | undefined | '_',
    end_at :: integer() | undefined | '_'
}).

-define(SHARD, ?COMMON_SHARD).
-define(MAX_SIZE, 30).

-endif.
