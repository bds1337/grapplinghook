//  Raging Deathmatch is an alternative deathmatch gametype for Warsow.
//  The only distinction from the default deathmatch is that the score is 
//  measured not by frags, but by a numeric equivalent of the beauty of
//  the shots.
//
//  Copyright (C) 2011-2016 Vitaly Minko <vitaly.minko@gmail.com>
//  Copyright (C) 2002-2009 The Warsow devteam
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//  Version 0.6 from 2 Oct 2016
//  Based on the DeathMatch gametype

// Do we have builtin math constants?
const float pi = 3.14159265f;

Vec3[] rdmVelocities( maxClients );
uint[] rdmTimes( maxClients );
uint rdmEndTime = 0;

Cvar rdmDebug( "rdm_debug", "0", CVAR_ARCHIVE );

///*****************************************************************
/// RDM FUNCTIONS
///*****************************************************************

int RDM_round( float f )
{
    if ( abs( f - floor( f ) ) < 0.5f )
        return int( f );
    else
        return int( f + f / abs( f ) );
}

float RDM_min( float a, float b )
{
    return ( a >= b ) ? b : a;
}

String RDM_getTimeString( int num )
{
    String minsString, secsString;
    String notime = "--:--";
    uint mtime, stime, min, sec;

    switch ( match.getState() )
    {
    case MATCH_STATE_WARMUP:
    case MATCH_STATE_COUNTDOWN:
        return notime;

    case MATCH_STATE_PLAYTIME:
        mtime = levelTime - rdmTimes[ num ];
        break;

    case MATCH_STATE_POSTMATCH:
    case MATCH_STATE_WAITEXIT:
        if ( rdmEndTime > 0 )
        {
            mtime = rdmEndTime - rdmTimes[ num ];
            break;
        }

    default:
        return notime;
    }

    stime = RDM_round( mtime / 1000.0f );
    min = stime / 60;
    sec = stime % 60;

    minsString = ( min >= 10 ) ? "" + min : "0" + min;
    secsString = ( sec >= 10 ) ? "" + sec : "0" + sec;

    return minsString + ":" + secsString;
}

float RDM_getDistance( Entity @a, Entity @b )
{
    return a.origin.distance( b.origin );
}

float RDM_getAngle( Vec3 a, Vec3 b )
{   
    Vec3 my_a = a;
    Vec3 my_b = b;

    if ( my_a.length() == 0 || my_b.length() == 0 )
        return 0;
  
    my_a.normalize();
    my_b.normalize();

    return abs( acos( my_a.x * my_b.x + my_a.y * my_b.y + my_a.z * my_b.z ) );
}

float RDM_getAngleFactor ( float angle )
{
    const float minAcuteFactor = 0.15f;
    const float minObtuseFactor = 0.30f;

    return ( angle < pi / 2.0f ) ?
        minAcuteFactor + ( 1.0f - minAcuteFactor ) * sin( angle ) :
        minObtuseFactor + ( 1.0f - minObtuseFactor ) * sin( angle );
}

Vec3 RDM_getVector( Entity @a, Entity @b )
{
    Vec3 ao;
    Vec3 bo;

    ao = a.origin;
    bo = b.origin;
    bo.x -= ao.x;
    bo.y -= ao.y;
    bo.z -= ao.z;

    return bo;
}

float RDM_getAnticampFactor ( float normalizedVelocity )
{
    // How fast does the factor grow?
    const float scale = 12.0f;

    return ( atan( scale * ( normalizedVelocity - 1.0f ) ) + pi / 2.0f ) / pi;
}

int RDM_calculateScore( Entity @target, Entity @attacker )
{
    // Default score for a "normal" shot
    const float defScore = 100.0f;
    // Normal speed
    const float normVelocity = 600.0f;
    // Normal distance
    const float normDist = 800.0f;

    Vec3 directionAt = RDM_getVector( attacker, target );
    Vec3 directionTa = RDM_getVector( target, attacker );

    /* Projection of the attacker's velocity relative to ground to the flat
     * surface that is perpendicular to the vector from the attacker
     * to the target */
    Vec3 velocityA = attacker.velocity;
    float angleA = RDM_getAngle( velocityA, directionAt );
    float projectionA = RDM_getAngleFactor( angleA ) * velocityA.length();

    /* Anti-camping dumping - we significantly decrease projection if the
     * attacker's velocity is lower than the normVelocity */
    float anticampFactor = RDM_getAnticampFactor( velocityA.length() / normVelocity );

    /* Projection of the target's velocity relative to the ground to the flat
     * surface that is perpendicular to the vector from the target
     * to the attacker */
    Vec3 velocityTg = rdmVelocities[ target.playerNum ];
    float angleTg = RDM_getAngle( velocityTg, directionTa );
    float projectionTg = RDM_getAngleFactor( angleTg ) * velocityTg.length();

    /* Projection of the target's velocity relative to the attacker to the flat
     * surface that is perpendicular to the vector from the target
     * to the attacker */
    Vec3 velocityTa = velocityTg - attacker.velocity;
    float angleTa = RDM_getAngle( velocityTa, directionTa );
    float projectionTa = RDM_getAngleFactor( angleTa ) * velocityTa.length();

    /* Choose minimal projection */
    float projectionT = RDM_min( projectionTg, projectionTa );

    float score = defScore
                * anticampFactor
                * pow( projectionA / normVelocity, 2.0f )
                * ( 1.0f + projectionT / normVelocity )
                * ( RDM_getDistance( attacker, target ) / normDist );

    return int( score );
}

// a player has just died. The script is warned about it so it can account scores
void RDM_playerKilled( Entity @target, Entity @attacker, Entity @inflicter )
{
    if ( match.getState() != MATCH_STATE_PLAYTIME )
        return;

    if ( @target.client == null )
        return;

    // punishment for suicide
    //if ( @attacker == null || attacker.playerNum == target.playerNum )
    //    target.client.stats.addScore( -500 );

    // update player score
    if ( @attacker != null && @attacker.client != null )
    {
       int score = RDM_calculateScore( target, attacker );
       
       //attacker.client.stats.addScore( score );
       //if ( score > attacker.client.stats.score )
       //     attacker.client.stats.setScore( score );

       if ( score < 500 )
       {
           G_PrintMsg( attacker.client.getEnt(),
                       "Shot score: (" + S_COLOR_CYAN + score + S_COLOR_WHITE + ")\n" );
       }
       if ( score >= 500 && score < 1000 )
       {
           attacker.client.addAward("Nice shot");
           G_PrintMsg( null,
                       attacker.client.name + " made a nice shot (" + S_COLOR_CYAN + score + S_COLOR_WHITE + ")\n" );
       }
       if ( score >= 1000 )
       {
           attacker.client.addAward(S_COLOR_RED + "Awesome shot");
           G_PrintMsg( null,
                       attacker.client.name + S_COLOR_RED + " is AWESOME!" + S_COLOR_WHITE + " (" + S_COLOR_CYAN + score + S_COLOR_WHITE + ")\n" );
       }
    }
}