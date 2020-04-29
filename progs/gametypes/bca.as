/* 
Copyright (C) 2009-2010 Chasseur de bots

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.
 
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
*/

uint caTimelimit1v1;

Cvar g_ca_timelimit1v1( "g_ca_timelimit1v1", "60", 0 );

Cvar g_noclass_inventory( "g_noclass_inventory", "gb mg rg gl rl pg lg eb cells shells grens rockets plasma lasers bullets", 0 );
Cvar g_class_strong_ammo( "g_class_strong_ammo", "1 75 20 20 40 125 180 15", 0 ); // GB MG RG GL RL PG LG EB

const int CA_ROUNDSTATE_NONE = 0;
const int CA_ROUNDSTATE_PREROUND = 1;
const int CA_ROUNDSTATE_ROUND = 2;
const int CA_ROUNDSTATE_ROUNDFINISHED = 3;
const int CA_ROUNDSTATE_POSTROUND = 4;

const int CA_LAST_MAN_STANDING_BONUS = 0; // 0 points for each frag

int[] caBonusScores( maxClients );
int[] caLMSCounts( GS_MAX_TEAMS ); // last man standing bonus for each team

bool[] isWelcomed( maxClients );


class cCARound
{
    int state;
    int numRounds;
    uint roundStateStartTime;
    uint roundStateEndTime;
    int countDown;
    Entity @alphaSpawn;
    Entity @betaSpawn;
	uint minuteLeft;
	int timelimit;
	int alpha_oneVS;
	int beta_oneVS;
	

    cCARound()
    {
        this.state = CA_ROUNDSTATE_NONE;
        this.numRounds = 0;
        this.roundStateStartTime = 0;
        this.countDown = 0;
		this.minuteLeft = 0;
		this.timelimit = 0;
        @this.alphaSpawn = null;
        @this.betaSpawn = null;
        
        this.alpha_oneVS = 0;
        this.beta_oneVS = 0;
    }

    ~cCARound() {}

    void setupSpawnPoints()
    {
        String className( "info_player_deathmatch" );
        Entity @spot1;
        Entity @spot2;
        Entity @spawn;
        float dist, bestDistance;

        // pick a random spawn first
        @spot1 = @GENERIC_SelectBestRandomSpawnPoint( null, className );

        // pick the furthest spawn second
		array<Entity @> @spawns = G_FindByClassname( className );
		@spawn = null;
        bestDistance = 0;
        @spot2 = null;
		
        for( uint i = 0; i < spawns.size(); i++ )
        {
			@spawn = spawns[i];
            dist = spot1.origin.distance( spawn.origin );
            if ( dist > bestDistance || @spot2 == null )
            {
                bestDistance = dist;
                @spot2 = @spawn;
            }
        }

        if ( random() > 0.5f )
        {
            @this.alphaSpawn = @spot1;
            @this.betaSpawn = @spot2;
        }
        else
        {
            @this.alphaSpawn = @spot2;
            @this.betaSpawn = @spot1;
        }
    }

    void newGame()
    {
        gametype.readyAnnouncementEnabled = false;
        gametype.scoreAnnouncementEnabled = true;
        gametype.countdownEnabled = false;

        // set spawnsystem type to not respawn the players when they die
        for ( int team = TEAM_PLAYERS; team < GS_MAX_TEAMS; team++ )
            gametype.setTeamSpawnsystem( team, SPAWNSYSTEM_HOLD, 0, 0, true );

        // clear scores

        Entity @ent;
        Team @team;
        int i;

        for ( i = TEAM_PLAYERS; i < GS_MAX_TEAMS; i++ )
        {
            @team = @G_GetTeam( i );
            team.stats.clear();

            // respawn all clients inside the playing teams
            for ( int j = 0; @team.ent( j ) != null; j++ )
            {
                @ent = @team.ent( j );
                ent.client.stats.clear(); // clear player scores & stats
            }
        }

        // clear bonuses
        for ( i = 0; i < maxClients; i++ )
            caBonusScores[i] = 0;

		this.clearLMSCounts();

        this.numRounds = 0;
        this.newRound();
        
        this.alpha_oneVS = 0;
        this.beta_oneVS = 0;

    }

    void addPlayerBonus( Client @client, int bonus )
    {
        if ( @client == null )
            return;

        caBonusScores[ client.playerNum ] += bonus;
    }

    int getPlayerBonusScore( Client @client )
    {
        if ( @client == null )
            return 0;

        return caBonusScores[ client.playerNum ];
    }

	void clearLMSCounts()
	{
		// clear last-man-standing counts
		for ( int i = TEAM_PLAYERS; i < GS_MAX_TEAMS; i++ )
			caLMSCounts[i] = 0;
	}

    void endGame()
    {
        this.newRoundState( CA_ROUNDSTATE_NONE );

        GENERIC_SetUpEndMatch();
    }

    void newRound()
    {
        G_RemoveDeadBodies();
        G_RemoveAllProjectiles();

        this.newRoundState( CA_ROUNDSTATE_PREROUND );
        this.numRounds++;
    }

    void newRoundState( int newState )
    {
        if ( newState > CA_ROUNDSTATE_POSTROUND )
        {
            this.newRound();
            return;
        }

        this.state = newState;
        this.roundStateStartTime = levelTime;

        switch ( this.state )
        {
        case CA_ROUNDSTATE_NONE:
            this.roundStateEndTime = 0;
            this.countDown = 0;
			this.timelimit = 0;
			this.minuteLeft = 0;
            break;

        case CA_ROUNDSTATE_PREROUND:
        {
            this.roundStateEndTime = levelTime + 7000;
            this.countDown = 5;
			this.timelimit = 0;
			this.minuteLeft = 0;

            // respawn everyone and disable shooting
            gametype.shootingDisabled = true;
            gametype.removeInactivePlayers = false;

            this.setupSpawnPoints();
	
			this.alpha_oneVS = 0;
			this.beta_oneVS = 0;

            Entity @ent;
            Team @team;

            for ( int i = TEAM_PLAYERS; i < GS_MAX_TEAMS; i++ )
            {
                @team = @G_GetTeam( i );

                // respawn all clients inside the playing teams
                for ( int j = 0; @team.ent( j ) != null; j++ )
                {
                    @ent = @team.ent( j );
                    ent.client.respawn( false );
                }
            }

			this.clearLMSCounts();
	    }
        break;

        case CA_ROUNDSTATE_ROUND:
        {
            gametype.shootingDisabled = false;
            gametype.removeInactivePlayers = true;
            this.countDown = 0;
            this.roundStateEndTime = 0;
            int soundIndex = G_SoundIndex( "sounds/announcer/countdown/fight0" + (1 + (rand() & 1)) );
            G_AnnouncerSound( null, soundIndex, GS_MAX_TEAMS, false, null );
            G_CenterPrintMsg( null, 'Fight!');
        }
        break;

        case CA_ROUNDSTATE_ROUNDFINISHED:
            gametype.shootingDisabled = true;
            this.roundStateEndTime = levelTime + 1500;
            this.countDown = 0;
			this.timelimit = 0;
			this.minuteLeft = 0;
            break;

        case CA_ROUNDSTATE_POSTROUND:
        {
            this.roundStateEndTime = levelTime + 3000;

            // add score to round-winning team
            Entity @ent;
            Entity @lastManStanding = null;
            Team @team;
            int count_alpha, count_beta;
            int count_alpha_total, count_beta_total;

            count_alpha = count_alpha_total = 0;
            @team = @G_GetTeam( TEAM_ALPHA );
            for ( int j = 0; @team.ent( j ) != null; j++ )
            {
                @ent = @team.ent( j );
                if ( !ent.isGhosting() )
                {
                    count_alpha++;
                    @lastManStanding = @ent;
                    // ch : add round
                    if( @ent.client != null )
                    	ent.client.stats.addRound();
                }
                count_alpha_total++;
            }

            count_beta = count_beta_total = 0;
            @team = @G_GetTeam( TEAM_BETA );
            for ( int j = 0; @team.ent( j ) != null; j++ )
            {
                @ent = @team.ent( j );
                if ( !ent.isGhosting() )
                {
                    count_beta++;
                    @lastManStanding = @ent;
                    // ch : add round
                    if( @ent.client != null )
                    	ent.client.stats.addRound();
                }
                count_beta_total++;
            }
            
            int soundIndex;

            if ( count_alpha > count_beta )
            {
                G_GetTeam( TEAM_ALPHA ).stats.addScore( 1 );

                soundIndex = G_SoundIndex( "sounds/announcer/ctf/score_team0" + (1 + (rand() & 1)) );
                G_AnnouncerSound( null, soundIndex, TEAM_ALPHA, false, null );
                soundIndex = G_SoundIndex( "sounds/announcer/ctf/score_enemy0" + (1 + (rand() & 1)) );
                G_AnnouncerSound( null, soundIndex, TEAM_BETA, false, null );

                if ( !gametype.isInstagib && count_alpha == 1 ) // he's the last man standing. Drop a bonus
                {
                    if ( count_beta_total > 1 )
                    {
                        lastManStanding.client.addAward( S_COLOR_GREEN + "Last Player Standing!" );
                        // ch :
                        if( alpha_oneVS > ONEVS_AWARD_COUNT )
                        	// lastManStanding.client.addMetaAward( "Last Man Standing" );
                        	lastManStanding.client.addAward( "Last Man Standing" );

                        this.addPlayerBonus( lastManStanding.client, caLMSCounts[TEAM_ALPHA] * CA_LAST_MAN_STANDING_BONUS );
                        GT_updateScore( lastManStanding.client );
                    }
                }
            }
            else if ( count_beta > count_alpha )
            {
                G_GetTeam( TEAM_BETA ).stats.addScore( 1 );

                soundIndex = G_SoundIndex( "sounds/announcer/ctf/score_team0" + (1 + (rand() & 1)) );
                G_AnnouncerSound( null, soundIndex, TEAM_BETA, false, null );
                soundIndex = G_SoundIndex( "sounds/announcer/ctf/score_enemy0" + (1 + (rand() & 1)) );
                G_AnnouncerSound( null, soundIndex, TEAM_ALPHA, false, null );

                if ( !gametype.isInstagib && count_beta == 1 ) // he's the last man standing. Drop a bonus
                {
                    if ( count_alpha_total > 1 )
                    {
                        lastManStanding.client.addAward( S_COLOR_GREEN + "Last Player Standing!" );
                        // ch :
                        if( beta_oneVS > ONEVS_AWARD_COUNT )
                        	// lastManStanding.client.addMetaAward( "Last Man Standing" );
                        	lastManStanding.client.addAward( "Last Man Standing" );

                        this.addPlayerBonus( lastManStanding.client, caLMSCounts[TEAM_BETA] * CA_LAST_MAN_STANDING_BONUS );
												GT_updateScore( lastManStanding.client );
                    }
                }
            }
			else // draw round
            {
                G_CenterPrintMsg( null, "Draw Round!" );
            }
        }
        break;

        default:
            break;
        }
    }

    void think()
    {
        if ( this.state == CA_ROUNDSTATE_NONE )
            return;
		
        if ( match.getState() != MATCH_STATE_PLAYTIME )
        {
            this.endGame();
            return;
        }

        if ( this.roundStateEndTime != 0 )
        {
            if ( this.roundStateEndTime < levelTime )
            {
                this.newRoundState( this.state + 1 );
                return;
            }

            if ( this.countDown > 0 )
            {
                // we can't use the automatic countdown announces because their are based on the
                // matchstate timelimit, and prerounds don't use it. So, fire the announces "by hand".
                int remainingSeconds = int( ( this.roundStateEndTime - levelTime ) * 0.001f ) + 1;
                if ( remainingSeconds < 0 )
                    remainingSeconds = 0;

                if ( remainingSeconds < this.countDown )
                {
                    this.countDown = remainingSeconds;

                    if ( this.countDown == 4 )
                    {
                        int soundIndex = G_SoundIndex( "sounds/announcer/countdown/ready0" + (1 + (rand() & 1)) );
                        G_AnnouncerSound( null, soundIndex, GS_MAX_TEAMS, false, null );
                    }
                    else if ( this.countDown <= 3 )
                    {
                        int soundIndex = G_SoundIndex( "sounds/announcer/countdown/" + this.countDown + "_0" + (1 + (rand() & 1)) );
                        G_AnnouncerSound( null, soundIndex, GS_MAX_TEAMS, false, null );

                    }
                    G_CenterPrintMsg( null, String( this.countDown ) );
                }
            }
        }

        // if one of the teams has no player alive move from CA_ROUNDSTATE_ROUND
        if ( this.state == CA_ROUNDSTATE_ROUND )
        {
			// 1 minute left if 1v1
			if( this.minuteLeft > 0 )
			{
				uint left = this.minuteLeft - levelTime;

				if ( caTimelimit1v1 != 0 && ( caTimelimit1v1 * 1000 ) == left )
				{
					if( caTimelimit1v1 < 60 )
					{
						G_CenterPrintMsg( null, caTimelimit1v1 + " seconds left. Hurry up!" );
					}
					else
					{
						uint minutes;					
						uint seconds = caTimelimit1v1 % 60;
						
						if( seconds == 0 )
						{
							minutes = caTimelimit1v1 / 60;
							if(minutes == 1) {
								G_CenterPrintMsg( null, minutes + " minute left. Hurry up!");
							} else {
								G_CenterPrintMsg( null, minutes + " minutes left. Hurry up!" );							
							}
						}
						else
						{
							minutes = ( caTimelimit1v1 - seconds ) / 60;
							G_CenterPrintMsg( null, minutes + " minutes and "+ seconds +" seconds left. Hurry up!"  );
						}
					}
				}
				
                int remainingSeconds = int( left * 0.001f ) + 1;
                if ( remainingSeconds < 0 )
                    remainingSeconds = 0;
				
				this.timelimit = remainingSeconds;
				match.setClockOverride( minuteLeft - levelTime );
				
				if( levelTime > this.minuteLeft )
				{
					G_CenterPrintMsg( null , S_COLOR_RED + 'Timelimit hit!');
					this.newRoundState( this.state + 1 );
				}
			}
		
			// if one of the teams has no player alive move from CA_ROUNDSTATE_ROUND
            Entity @ent;
            Team @team;
            int count;

            for ( int i = TEAM_ALPHA; i < GS_MAX_TEAMS; i++ )
            {
                @team = @G_GetTeam( i );
                count = 0;

                for ( int j = 0; @team.ent( j ) != null; j++ )
                {
                    @ent = @team.ent( j );
                    if ( !ent.isGhosting() )
                        count++;
                }

                if ( count == 0 )
                {
                    this.newRoundState( this.state + 1 );

                    // Remove hook for new round
                    //int numPlayer = ent.client.get_playerNum();
                    //Hookers[ numPlayer ].isActive = false;

                    break; // no need to continue
                }
            }
        }
    }

    void playerKilled( Entity @target, Entity @attacker, Entity @inflictor )
    {
        Entity @ent;
        Team @team;

        if ( this.state != CA_ROUNDSTATE_ROUND )
            return;

        if ( @target != null && @target.client != null && @attacker != null && @attacker.client != null )
        {
			if ( gametype.isInstagib )
			{
				G_PrintMsg( target, "You were fragged by " + attacker.client.name + "\n" );
			}
			else
			{
				// report remaining health/armor of the killer
				G_PrintMsg( target, "You were fragged by " + attacker.client.name + " (health: " + rint( attacker.health ) + ", armor: " + rint( attacker.client.armor ) + ")\n" );
			}

            // if the attacker is the only remaining player on the team,
            // report number or remaining enemies

            int attackerCount = 0, targetCount = 0;

            // count attacker teammates
            @team = @G_GetTeam( attacker.team );
            for ( int j = 0; @team.ent( j ) != null; j++ )
            {
                @ent = @team.ent( j );
                if ( !ent.isGhosting() )
                    attackerCount++;
            }

            // count target teammates
            @team = @G_GetTeam( target.team );
            for ( int j = 0; @team.ent( j ) != null; j++ )
            {
                @ent = @team.ent( j );
                if ( !ent.isGhosting() && @ent != @target )
                    targetCount++;
            }

			// amount of enemies for the last-man-standing award
			if ( targetCount == 1 && caLMSCounts[target.team] == 0 )
				caLMSCounts[target.team] = attackerCount;

            if ( attackerCount == 1 && targetCount == 1 )
            {
                G_PrintMsg( null, "1v1! Good luck!\n" );
                attacker.client.addAward( "1v1! Good luck!" );

                // find the alive player in target team again (doh)
                @team = @G_GetTeam( target.team );
                for ( int j = 0; @team.ent( j ) != null; j++ )
                {
                    @ent = @team.ent( j );
                    if ( ent.isGhosting() || @ent == @target )
                        continue;

                    ent.client.addAward( S_COLOR_ORANGE + "1v1! Good luck!" );
                    break;
                }

				this.minuteLeft = levelTime + ( caTimelimit1v1 * 1000 );
            }
            else if ( attackerCount == 1 && targetCount > 1 )
            {
                attacker.client.addAward( "1v" + targetCount + "! You're on your own!" );

                // console print for the team
                @team = @G_GetTeam( attacker.team );
                for ( int j = 0; @team.ent( j ) != null; j++ )
                {
                    G_PrintMsg( team.ent( j ), "1v" + targetCount + "! " + attacker.client.name + " is on its own!\n" );
                }
                
                // ch : update last man standing count
                if( attacker.team == TEAM_ALPHA && targetCount > alpha_oneVS )
                	alpha_oneVS = targetCount;
                else if( attacker.team == TEAM_BETA && targetCount > beta_oneVS )
                	beta_oneVS = targetCount;
            }
            else if ( attackerCount > 1 && targetCount == 1 )
            {
                Entity @survivor;

                // find the alive player in target team again (doh)
                @team = @G_GetTeam( target.team );
                for ( int j = 0; @team.ent( j ) != null; j++ )
                {
                    @ent = @team.ent( j );
                    if ( ent.isGhosting() || @ent == @target )
                        continue;

                    ent.client.addAward( "1v" + attackerCount + "! You're on your own!" );
                    @survivor = @ent;
                    break;
                }

                // console print for the team
                for ( int j = 0; @team.ent( j ) != null; j++ )
                {
                    @ent = @team.ent( j );
                    G_PrintMsg( ent, "1v" + attackerCount + "! " + survivor.client.name + " is on its own!\n" );
                }
                
                // ch : update last man standing count
                if( target.team == TEAM_ALPHA && attackerCount > alpha_oneVS )
					alpha_oneVS = attackerCount;
				else if( target.team == TEAM_BETA && attackerCount > beta_oneVS )
					beta_oneVS = attackerCount;
            }
            
            // check for generic awards for the frag
            if( attacker.team != target.team )
				award_playerKilled( @target, @attacker, @inflictor );
        }
        
        // ch : add a round for victim
        if ( @target != null && @target.client != null )
        	target.client.stats.addRound();
    }
}

cCARound caRound;

///*****************************************************************
/// NEW MAP ENTITY DEFINITIONS
///*****************************************************************


///*****************************************************************
/// LOCAL FUNCTIONS
///*****************************************************************

void CA_SetUpWarmup()
{
    GENERIC_SetUpWarmup();

    // set spawnsystem type to instant while players join
    for ( int team = TEAM_PLAYERS; team < GS_MAX_TEAMS; team++ )
        gametype.setTeamSpawnsystem( team, SPAWNSYSTEM_INSTANT, 0, 0, false );
}

void CA_SetUpCountdown()
{
    gametype.shootingDisabled = true;
    gametype.readyAnnouncementEnabled = false;
    gametype.scoreAnnouncementEnabled = false;
    gametype.countdownEnabled = false;
    G_RemoveAllProjectiles();

    // lock teams
    bool anyone = false;
    if ( gametype.isTeamBased )
    {
        for ( int team = TEAM_ALPHA; team < GS_MAX_TEAMS; team++ )
        {
            if ( G_GetTeam( team ).lock() )
                anyone = true;
        }
    }
    else
    {
        if ( G_GetTeam( TEAM_PLAYERS ).lock() )
            anyone = true;
    }

    if ( anyone )
        G_PrintMsg( null, "Teams locked.\n" );

    // Countdowns should be made entirely client side, because we now can

    int soundIndex = G_SoundIndex( "sounds/announcer/countdown/get_ready_to_fight0" + (1 + (rand() & 1)) );
    G_AnnouncerSound( null, soundIndex, GS_MAX_TEAMS, false, null );
}

///*****************************************************************
/// MODULE SCRIPT CALLS
///*****************************************************************

bool GT_Command( Client @client, const String &cmdString, const String &argsString, int argc )
{
    //Hook hookobj;

    if ( cmdString == "gametype" )
    {
        String response = "";
        Cvar fs_game( "fs_game", "", 0 );
        String manifest = gametype.manifest;

        response += "\n";
        response += "Gametype " + gametype.name + " : " + gametype.title + "\n";
        response += "----------------\n";
        response += "Version: " + gametype.version + "\n";
        response += "Author: " + gametype.author + "\n";
        response += "Mod: " + fs_game.string + (!manifest.empty() ? " (manifest: " + manifest + ")" : "") + "\n";
        response += "----------------\n";

        G_PrintMsg( client.getEnt(), response );
        return true;
    }
    else if ( cmdString == "cvarinfo" )
    {
        GENERIC_CheatVarResponse( client, cmdString, argsString, argc );
        return true;
    }
    else if ( cmdString == "+hook" )
    {

        //Hook hookobj;
        int numPlayer = client.get_playerNum();
        Vec3 fwd, _right, _up;
        client.getEnt().angles.angleVectors(fwd, _right, _up);

        Hookers[ numPlayer ].isActive = true;
        Hookers[ numPlayer ].fwdTarget = fwd;
    }
    else if ( cmdString == "-hook" )
    {
        if ( client.getEnt().isGhosting() )
            return false;
        
        int numPlayer = client.get_playerNum();
        Hookers[ numPlayer ].isActive = false;
        
    }
    else if ( cmdString == "gametypemenu" )
    {
        String command = "mecu \"How this fucking thing work?\""
            + " \"Bind grappling hook\" \"say h +hook\""
            + " \"RL + LG\" \"weapselect rl\""
            + " \"EB + LG\" \"weapselect lg\"";
            
        client.execGameCommand( command );

        return true;
    }
    // Callvote stuff
    else if ( cmdString == "callvotevalidate" )
    {
        String votename = argsString.getToken( 0 );
        if ( votename == "knockback" )
        {
            String voteArg = argsString.getToken( 1 );
            if ( voteArg.len() < 1 )
            {
                client.printMessage( "Callvote " + votename + " requires at least one argument\n" );
                return false;
            }

            int value = voteArg.toInt();
            if ( value >= 0 && value < 6 )
            {
                return true;
            }

            return false;
        }
        if ( votename == "hook_enabled" )
        {
            String voteArg = argsString.getToken( 1 );
            if ( voteArg.len() < 1 )
            {
                client.printMessage( "Callvote " + votename + " requires at least one argument\n" );
                return false;
            }

            int value = voteArg.toInt();
            if ( value >= 0 )
            {
                return true;
            }

            return false;
        }
        if ( votename == "hook_limit" )
        {
            String voteArg = argsString.getToken( 1 );
            if ( voteArg.len() < 1 )
            {
                client.printMessage( "Callvote " + votename + " requires at least one argument\n" );
                return false;
            }

            int value = voteArg.toInt();
            if ( value >= 0 )
            {
                return true;
            }

            return false;
        }
        if ( votename == "hook_insta" )
        {
            String voteArg = argsString.getToken( 1 );
            if ( voteArg.len() < 1 )
            {
                client.printMessage( "Callvote " + votename + " requires at least one argument\n" );
                return false;
            }

            int value = voteArg.toInt();
            if ( value >= 0 )
            {
                return true;
            }

            return false;
        }

        client.printMessage( "Unknown callvote " + votename + "\n" );
        return false;
    }
    else if ( cmdString == "callvotepassed" )
    {
        String votename = argsString.getToken( 0 );
        String knockback_arg = "g_knockback_scale ";
        String hook_arg = "hook_enabled ";
        String hook_limit_arg = "hook_limit ";
        String hook_insta_arg = "hook_insta ";
        if ( votename == "knockback" )
        {
            knockback_arg += argsString.getToken( 1 ).toInt();
            G_CmdExecute (knockback_arg);
        }
        if ( votename == "hook_enabled" )
        {
            hook_arg += argsString.getToken( 1 ).toInt();
            G_CmdExecute (hook_arg);
        }
        if ( votename == "hook_limit" )
        {
            hook_limit_arg += argsString.getToken( 1 ).toInt();
            G_CmdExecute (hook_limit_arg);
        }
        if ( votename == "hook_insta" )
        {
            hook_insta_arg += argsString.getToken( 1 ).toInt();
            G_CmdExecute (hook_insta_arg);
        }
    }

    return false;
}

// When this function is called the weights of items have been reset to their default values,
// this means, the weights *are set*, and what this function does is scaling them depending
// on the current bot status.
// Player, and non-item entities don't have any weight set. So they will be ignored by the bot
// unless a weight is assigned here.
bool GT_UpdateBotStatus( Entity @ent )
{
    Entity @goal;
    Bot @bot;

    @bot = @ent.client.getBot();
    if ( @bot == null )
        return false;

    float offensiveStatus = GENERIC_OffensiveStatus( ent );

    // loop all the goal entities
    for ( int i = AI::GetNextGoal( AI::GetRootGoal() ); i != AI::GetRootGoal(); i = AI::GetNextGoal( i ) )
    {
        @goal = @AI::GetGoalEntity( i );

        // by now, always full-ignore not solid entities
        if ( goal.solid == SOLID_NOT )
        {
            bot.setGoalWeight( i, 0 );
            continue;
        }

        if ( @goal.client != null )
        {
            bot.setGoalWeight( i, GENERIC_PlayerWeight( ent, goal ) * 2.5 * offensiveStatus );
            continue;
        }

        // ignore it
        bot.setGoalWeight( i, 0 );
    }

    return true; // handled by the script
}

// select a spawning point for a player
Entity @GT_SelectSpawnPoint( Entity @self )
{
    if ( caRound.state == CA_ROUNDSTATE_PREROUND )
    {
        if ( self.team == TEAM_ALPHA )
            return @caRound.alphaSpawn;

        if ( self.team == TEAM_BETA )
            return @caRound.betaSpawn;
    }

    return GENERIC_SelectBestRandomSpawnPoint( self, "info_player_deathmatch" );
}

String @GT_ScoreboardMessage( uint maxlen )
{
    String scoreboardMessage = "";
    String entry;
    Team @team;
    Entity @ent;
    int i, t;

    for ( t = TEAM_ALPHA; t < GS_MAX_TEAMS; t++ )
    {
        @team = @G_GetTeam( t );

        // &t = team tab, team tag, team score (doesn't apply), team ping (doesn't apply)
        entry = "&t " + t + " " + team.stats.score + " " + team.ping + " ";
        if ( scoreboardMessage.len() + entry.len() < maxlen )
            scoreboardMessage += entry;

        for ( i = 0; @team.ent( i ) != null; i++ )
        {
            @ent = @team.ent( i );

            int playerID = ( ent.isGhosting() && ( match.getState() == MATCH_STATE_PLAYTIME ) ) ? -( ent.playerNum + 1 ) : ent.playerNum;

            if ( gametype.isInstagib )
            {
                int weap_acc = 0;
                if ( ent.client.stats.accuracyHits( AMMO_INSTAS ) > 0 )
                        weap_acc = (float(ent.client.stats.accuracyHits( AMMO_INSTAS ) ) / 
                            float(ent.client.stats.accuracyShots( AMMO_INSTAS ))) * 100;
                // "Name Clan Score Ping R"
                entry = "&p " + playerID + " " + ent.client.clanName + " "
                        + ent.client.stats.score + " " // Best shot
                        + 1 + " "
                        + weap_acc + " "
                        + ent.client.ping + " " + ( ent.client.isReady() ? "1" : "0" ) + " ";
            }
            else
            {   
                //need choose best weap for acc
                int weap_acc, weap_newacc = 0;
                int counter = AMMO_GUNBLADE;
                int weap_pic = 1;
                while ( counter < AMMO_INSTAS )
                { 
                    if ( ent.client.stats.accuracyHits( counter ) > 0 )
                    {
                        weap_acc = (float(ent.client.stats.accuracyHits( counter ) ) / 
                            float(ent.client.stats.accuracyShots( counter ))) * 100;
                        if ( weap_acc > weap_newacc )
                        {
                            weap_newacc = weap_acc;
                            weap_pic =  2*(counter - AMMO_GUNBLADE) + 1;
                        }
                    }
                    counter++;
                }
                // "Name Clan Score Frags Ping R"
                // 1 = GB, 3 = MG, 5 = rg, 7 = NADE 
                entry = "&p " + playerID + " " + ent.client.clanName + " "
                        + ent.client.stats.score + " " + ent.client.stats.frags + " "
                        + weap_pic + " "
                        + weap_newacc + " "
                        + ent.client.ping + " " 
                        + ( ent.client.isReady() ? "1" : "0" ) + " ";
            }

            if ( scoreboardMessage.len() + entry.len() < maxlen )
                scoreboardMessage += entry;
        }
    }

    return scoreboardMessage;
}

//
void GT_updateScore( Client @client )
{
    if ( @client != null )
    {
        if ( gametype.isInstagib )
        {
            // FOLLOW RDM RULES. SET BEST SHOT SCORE
            client.stats.setScore( client.stats.frags + caRound.getPlayerBonusScore( client ) );
            //client.stats.addScore( 0 ); // zaglyshka
        }
        else
            client.stats.setScore( int( client.stats.totalDamageGiven * 0.01 ) + caRound.getPlayerBonusScore( client ) );
    }
}

// Some game actions trigger score events. These are events not related to killing
// oponents, like capturing a flag
// Warning: client can be null
void GT_ScoreEvent( Client @client, const String &score_event, const String &args )
{
    if ( score_event == "connect" )
    {
        isWelcomed[ client.getEnt().playerNum ] = false;
    }
    if ( score_event == "dmg" )
    {
        if ( match.getState() == MATCH_STATE_PLAYTIME )
        {
			GT_updateScore( client );
        }
    }
    else if ( score_event == "kill" )
    {
        Entity @attacker = null;

        if ( @client != null )
            @attacker = @client.getEnt();

        int arg1 = args.getToken( 0 ).toInt();
        int arg2 = args.getToken( 1 ).toInt();

        // target, attacker, inflictor
        caRound.playerKilled( G_GetEntity( arg1 ), attacker, G_GetEntity( arg2 ) );
    
        //rdm fun stuff (only for instagib)
        if ( gametype.isInstagib )
        {
            RDM_playerKilled( G_GetEntity( arg1 ), attacker, G_GetEntity( arg2 ) ); 
        }

		if ( match.getState() == MATCH_STATE_PLAYTIME )
		{
			GT_updateScore( client );
		}
    }
    else if ( score_event == "award" )
    {
    }
	else if( score_event == "rebalance" || score_event == "shuffle" )
	{
		// end round when in match
		if ( ( @client == null ) && ( match.getState() == MATCH_STATE_PLAYTIME ) )
		{
			caRound.newRoundState( CA_ROUNDSTATE_ROUNDFINISHED );
		}	
	}
}

// a player is being respawned. This can happen from several ways, as dying, changing team,
// being moved to ghost state, be placed in respawn queue, being spawned from spawn queue, etc
void GT_PlayerRespawn( Entity @ent, int old_team, int new_team )
{
    if ( new_team != TEAM_SPECTATOR && !isWelcomed[ ent.playerNum ] )
    {
        String welcome = "";
        welcome = S_COLOR_WHITE
                + "Welcome to " + S_COLOR_YELLOW + gametype.title + "!\n"
                + S_COLOR_WHITE + "Grappling hook usage:\n"
                + "Type " + S_COLOR_GREEN + "bind your_key +hook" + S_COLOR_WHITE
                + " in the console... hf\n";
        G_PrintMsg( ent, welcome );
        isWelcomed[ ent.playerNum ] = true;
    }

    if ( ent.isGhosting() )
	{
		ent.svflags &= ~SVF_FORCETEAM;
        return;
	}


    if ( gametype.isInstagib )
    {
        ent.client.inventoryGiveItem( WEAP_INSTAGUN );
        ent.client.inventorySetCount( AMMO_INSTAS, 1 );
        ent.client.inventorySetCount( AMMO_WEAK_INSTAS, 1 );
     
        // set player movement to pass through other players
        // only for instamod
        ent.client.pmoveFeatures = ent.client.pmoveFeatures | PMFEAT_GHOSTMOVE;
    }
    else
    {
    	// give the weapons and ammo as defined in cvars
    	String token, weakammotoken, ammotoken;
    	String itemList = g_noclass_inventory.string;
    	String ammoCounts = g_class_strong_ammo.string;

    	ent.client.inventoryClear();

        for ( int i = 0; ;i++ )
        {
            token = itemList.getToken( i );
            if ( token.len() == 0 )
                break; // done

            Item @item = @G_GetItemByName( token );
            if ( @item == null )
                continue;

            ent.client.inventoryGiveItem( item.tag );

            // if it's ammo, set the ammo count as defined in the cvar
            if ( ( item.type & IT_AMMO ) != 0 )
            {
                token = ammoCounts.getToken( item.tag - AMMO_GUNBLADE );

                if ( token.len() > 0 )
                {
                    ent.client.inventorySetCount( item.tag, token.toInt() );
                }
            }
        }

        // give armor
        ent.client.armor = 150;

        // select rocket launcher
        ent.client.selectWeapon( WEAP_ROCKETLAUNCHER );
    }

    // auto-select best weapon in the inventory
    if( ent.client.pendingWeapon == WEAP_NONE )
		ent.client.selectWeapon( -1 );

	ent.svflags |= SVF_FORCETEAM;

    // Disable active hook
    int numPlayer = ent.client.get_playerNum();
    Hookers[ numPlayer ].isActive = false;

    // add a teleportation effect
    ent.respawnEffect();
}

// Thinking function. Called each frame
void GT_ThinkRules()
{
    if ( match.scoreLimitHit() || match.timeLimitHit() || match.suddenDeathFinished() )
        match.launchState( match.getState() + 1 );

	GENERIC_Think();

    //Hook
    for ( int i = 0; i < maxClients; i++ )
    {
        Hookers[i].Update(); 
    }

    // print count of players alive and show class icon in the HUD

    Team @team;
    int[] alive( GS_MAX_TEAMS );

    alive[TEAM_SPECTATOR] = 0;
    alive[TEAM_PLAYERS] = 0;
    alive[TEAM_ALPHA] = 0;
    alive[TEAM_BETA] = 0;

    for ( int t = TEAM_ALPHA; t < GS_MAX_TEAMS; t++ )
    {
        @team = @G_GetTeam( t );
        for ( int i = 0; @team.ent( i ) != null; i++ )
        {
            if ( !team.ent( i ).isGhosting() )
                alive[t]++;
        }
    }

    G_ConfigString( CS_GENERAL, "" + alive[TEAM_ALPHA] );
    G_ConfigString( CS_GENERAL + 1, "" + alive[TEAM_BETA] );

    for ( int i = 0; i < maxClients; i++ )
    {
        Client @client = @G_GetClient( i );
        /*
        if ( client.stats.accuracyHits( AMMO_LASERS ) > 0 )
        {
            String stuff = "";
            float laser_acc = float(client.stats.accuracyHits( AMMO_LASERS ) ) / float(client.stats.accuracyShots( AMMO_LASERS ));
            //stuff += client.stats.accuracyHits( AMMO_LASERS ) + " | " + client.stats.accuracyShots( AMMO_LASERS );
            stuff += int( laser_acc * 100);
            G_PrintMsg( client.getEnt(), stuff + "%\n" );
        }
        */
        if ( match.getState() >= MATCH_STATE_POSTMATCH || match.getState() < MATCH_STATE_PLAYTIME )
        {
            client.setHUDStat( STAT_MESSAGE_ALPHA, 0 );
            client.setHUDStat( STAT_MESSAGE_BETA, 0 );
            client.setHUDStat( STAT_IMAGE_BETA, 0 );
        }
        else
        {
            client.setHUDStat( STAT_MESSAGE_ALPHA, CS_GENERAL );
            client.setHUDStat( STAT_MESSAGE_BETA, CS_GENERAL + 1 );
        }

        if ( client.getEnt().isGhosting()
                || match.getState() >= MATCH_STATE_POSTMATCH )
        {
            client.setHUDStat( STAT_IMAGE_BETA, 0 );
        }
    }

    if ( match.getState() >= MATCH_STATE_POSTMATCH )
        return;

    caRound.think();
}

// The game has detected the end of the match state, but it
// doesn't advance it before calling this function.
// This function must give permission to move into the next
// state by returning true.
bool GT_MatchStateFinished( int incomingMatchState )
{
    // ** MISSING EXTEND PLAYTIME CHECK **

    if ( match.getState() <= MATCH_STATE_WARMUP && incomingMatchState > MATCH_STATE_WARMUP
            && incomingMatchState < MATCH_STATE_POSTMATCH )
        match.startAutorecord();

    if ( match.getState() == MATCH_STATE_POSTMATCH )
        match.stopAutorecord();

    return true;
}

// the match state has just moved into a new state. Here is the
// place to set up the new state rules
void GT_MatchStateStarted()
{
    switch ( match.getState() )
    {
    case MATCH_STATE_WARMUP:
        CA_SetUpWarmup();
        break;

    case MATCH_STATE_COUNTDOWN:
        CA_SetUpCountdown();
        break;

    case MATCH_STATE_PLAYTIME:
        caRound.newGame();
        break;

    case MATCH_STATE_POSTMATCH:
        caRound.endGame();
        break;

    default:
        break;
    }
}

// the gametype is shutting down cause of a match restart or map change
void GT_Shutdown()
{
}

// The map entities have just been spawned. The level is initialized for
// playing, but nothing has yet started.
void GT_SpawnGametype()
{
}

// Important: This function is called before any entity is spawned, and
// spawning entities from it is forbidden. If you want to make any entity
// spawning at initialization do it in GT_SpawnGametype, which is called
// right after the map entities spawning.

void GT_InitGametype()
{
    gametype.title = "Blessed Clan Arena";
    gametype.version = "69.420";
    gametype.author = "wsw devs + bes#4339";

    // if the gametype doesn't have a config file, create it
    if ( !G_FileExists( "configs/server/gametypes/" + gametype.name + ".cfg" ) )
    {
        String config;

        // the config file doesn't exist or it's empty, create it
        config = "// '" + gametype.title + "' gametype configuration file\n"
                 + "// This config will be executed each time the gametype is started\n"
                 + "\n\n// map rotation\n"
                 + "set g_instajump \"1\"\n"
                 + "set g_maplist \"wfca1\" // list of maps in automatic rotation\n"
                 + "set g_maprotation \"0\"   // 0 = same map, 1 = in order, 2 = random\n"
                 + "\n// game settings\n"
                 + "set g_scorelimit \"11\"\n"
                 + "set g_timelimit \"0\"\n"
                 + "set g_warmup_timelimit \"1\"\n"
                 + "set g_match_extendedtime \"0\"\n"
                 + "set g_allow_falldamage \"0\"\n"
                 + "set g_allow_selfdamage \"0\"\n"
                 + "set g_allow_teamdamage \"0\"\n"
                 + "set g_allow_stun \"0\"\n"
                 + "set g_teams_maxplayers \"8\"\n"
                 + "set g_teams_allow_uneven \"0\"\n"
                 + "set g_countdown_time \"3\"\n"
                 + "set g_maxtimeouts \"1\" // -1 = unlimited\n"
                 + "\n// gametype settings\n"
				 + "set g_ca_timelimit1v1 \"60\"\n"
                 + "\n// classes settings\n"
                 + "set g_noclass_inventory \"gb mg rg gl rl pg lg eb cells shells grens rockets plasma lasers bolts bullets\"\n"
                 + "set g_class_strong_ammo \"1 75 15 20 20 125 140 10\" // GB MG RG GL RL PG LG EB\n"
                 + "set rdm_debug \"0\"\n"
                 + "set hook_enabled \"1\"\n"
                 + "set hook_limit \"1\"\n"
                 + "set hook_insta \"1\"\n"
                 + "\necho \"" + gametype.name + ".cfg executed\"\n";

        G_WriteFile( "configs/server/gametypes/" + gametype.name + ".cfg", config );
        G_Print( "Created default config file for '" + gametype.name + "'\n" );
        G_CmdExecute( "exec configs/server/gametypes/" + gametype.name + ".cfg silent" );
    }

	caTimelimit1v1 = g_ca_timelimit1v1.integer;

    gametype.spawnableItemsMask = 0;
    gametype.respawnableItemsMask = 0;
    gametype.dropableItemsMask = 0;
    gametype.pickableItemsMask = 0;

    gametype.isTeamBased = true;
    gametype.isRace = false;
    gametype.hasChallengersQueue = false;
    gametype.maxPlayersPerTeam = 0;

    gametype.ammoRespawn = 20;
    gametype.armorRespawn = 25;
    gametype.weaponRespawn = 15;
    gametype.healthRespawn = 25;
    gametype.powerupRespawn = 90;
    gametype.megahealthRespawn = 20;
    gametype.ultrahealthRespawn = 60;

    gametype.readyAnnouncementEnabled = false;
    gametype.scoreAnnouncementEnabled = false;
    gametype.countdownEnabled = false;
    gametype.mathAbortDisabled = false;
    gametype.shootingDisabled = false;
    gametype.infiniteAmmo = true;
    gametype.canForceModels = true;
    gametype.canShowMinimap = false;
    gametype.teamOnlyMinimap = true;
    gametype.removeInactivePlayers = true;

	gametype.mmCompatible = true;
	
    gametype.spawnpointRadius = 256;

    if ( gametype.isInstagib )
        gametype.spawnpointRadius *= 2;

    // set spawnsystem type to instant while players join
    for ( int team = TEAM_PLAYERS; team < GS_MAX_TEAMS; team++ )
        gametype.setTeamSpawnsystem( team, SPAWNSYSTEM_INSTANT, 0, 0, false );

    // define the scoreboard layout
    if ( gametype.isInstagib )
    {
        G_ConfigString( CS_SCB_PLAYERTAB_LAYOUT, "%n 112 %s 52 %i 52 %p 18 %i 28 %l 48 %r l1" );
        G_ConfigString( CS_SCB_PLAYERTAB_TITLES, "Name Clan Score Acc . Ping R" );
    }
    else
    {
        G_ConfigString( CS_SCB_PLAYERTAB_LAYOUT, "%n 112 %s 52 %i 52 %i 52 %p 18 %i 28 %l 48 %r l1" );
        G_ConfigString( CS_SCB_PLAYERTAB_TITLES, "Name Clan Score Frags Acc . Ping R" );
    }

    // add commands
    G_RegisterCommand( "gametype" );
    //G_RegisterCommand( "help" );
    G_RegisterCommand( "+hook" );
    G_RegisterCommand( "-hook" );
    
    //G_RegisterCommand( "gametypemenu" );

    G_RegisterCallvote( "knockback", "<0-5>", "integer", "Knockback scale" );
    G_RegisterCallvote( "hook_enabled", "<1 or 0>", "bool", "Enables or disables grappling hook usage" );
    G_RegisterCallvote( "hook_limit", "<1 or 0>", "bool", "Enables or disables grappling hook speed limit" );
    G_RegisterCallvote( "hook_insta", "<1 or 0>", "bool", "Enables or disables grappling hook instantly pulls player" );


    for ( int i = 0; i < maxClients; i++ )
    {
        @Hookers[i].client = @G_GetClient(i);
        @Hookers[i].player = @G_GetClient(i).getEnt();

        isWelcomed[ i ] = true;
    }

    G_Print( "Gametype '" + gametype.title + "' initialized\n" );
}
